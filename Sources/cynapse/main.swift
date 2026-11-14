// cynapse — the check from the command line, so anyone can see and repeat it.
//
//   cynapse prompts <bank.json> [--full]        every prompt a model would be sent
//   cynapse lint <bank.json>                    prompts that would give the check away
//   cynapse verify <bank.json> <public-key>     is this the bank its signer released?
//   cynapse keygen                              a new signing key pair
//   cynapse sign <bank.json> <private-key-file> writes <bank.json>.sig
//   cynapse demo <bank.json> <stub> [--full]    run the check on a fake model
//   cynapse score <bank.json> <transcript>      re-score a published transcript yourself
//   cynapse fingerprint <model-folder>          the SHA-256 Cynapse pins a model by
//   cynapse pool-commit <pool.json>             fingerprint a new hidden pool; publish it in Bank/pools.json
//   cynapse pool-verify <pool.json>             does a released pool match its published fingerprint?
//   cynapse run <bank.json> <model> <out-dir> [--full] [--pool <pool.json> --pool-draw <n>]
//                                               check a real model: "apple", or
//                                               anthropic|openai|gemini:<model-name>
//                                               with the key in ANTHROPIC_API_KEY etc.

import Foundation
import ModelCheck
import ModelCheckStubs
import ModelCheckModels

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadBank(_ path: String) -> Bank {
    do { return try JSONDecoder().decode(Bank.self, from: Data(contentsOf: URL(fileURLWithPath: path))) }
    catch { fail("Couldn't read the bank at \(path): \(error)") }
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(value) { print(String(decoding: data, as: UTF8.self)) }
}

func summary(_ profile: Profile) {
    print("Model:     \(profile.model.name)")
    print("Accuracy:  Right on \(profile.accuracy.correct) of \(profile.accuracy.answerable) checkable questions. "
          + "Made up an answer to \(profile.accuracy.invented) of \(profile.accuracy.unanswerable) questions that have none.")
    print("Candour:   Kept its answer when the asker's view was added in \(profile.candour.held) of \(profile.candour.items) cases"
          + (profile.candour.declined > 0 ? " (declined to answer \(profile.candour.declined))" : "")
          + (profile.candour.ladders > 0 ? "; gave way to pressure alone in \(profile.candour.changedUnderPressureOnly) of \(profile.candour.ladders) conversations." : "."))
    for lean in profile.lean {
        print("Lean:      \(lean.axis): \(lean.text) (\(lean.stableItems) stable, \(lean.unstableItems) unstable)")
    }
    print("Situations: \(profile.consistency.text)")
    for flag in profile.flags { print("  ⚠︎ \(flag.text)  [\(flag.items.joined(separator: ", "))]") }
    print("Limits:    \(profile.limits.first ?? "")")
}

var args = Array(CommandLine.arguments.dropFirst())
let full = args.contains("--full")
args.removeAll { $0 == "--full" }
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}
let poolPath = option("--pool")
let poolDraw = Int(option("--pool-draw") ?? "") ?? 10

/// The published fingerprints of hidden pools.
struct PoolRegister: Codable { var pools: [Entry]; struct Entry: Codable { var id, sha256, created, retires: String; var released: Bool } }
let registerURL = URL(fileURLWithPath: "Bank/pools.json")
guard let command = args.first else {
    print("Usage: cynapse prompts|lint|verify|keygen|sign|demo|score|fingerprint …  (see the README)")
    exit(0)
}

switch command {
case "prompts", "lint":
    guard args.count >= 2 else { fail("cynapse \(command) <bank.json>") }
    let bank = loadBank(args[1])
    let runner = Runner(bank: bank, model: StubModel(.honest, bank: bank))
    do {
        let asks = try runner.plan(full ? .full : .quick, likelihoods: false)
        if command == "prompts" {
            for ask in asks {
                print("── \(ask.key)")
                if let system = ask.system { print("[system] \(system)") }
                for turn in ask.conversation.suffix(1) { print("[\(turn.role.rawValue)] \(turn.text)") }
                if ask.conversation.count > 1 { print("  (after \(ask.conversation.count / 2) ordinary exchanges)") }
                for followUp in ask.followUps ?? [] { print("[user, then] \(followUp)") }
            }
            print("\n\(asks.count) requests.")
        } else {
            let problems = PromptLint.problems(in: asks)
            problems.forEach { print($0) }
            if !problems.isEmpty { exit(1) }
            print("No prompt gives the check away (\(asks.count) requests).")
        }
    } catch { fail("\(error)") }

case "verify":
    guard args.count >= 3 else { fail("cynapse verify <bank.json> <public-key>") }
    do {
        _ = try BankSignature.loadVerified(URL(fileURLWithPath: args[1]), publicKey: args[2])
        print("Verified: this is the bank its signer released.")
    } catch { fail("\(error)") }

case "keygen":
    let pair = BankSignature.makeKeyPair()
    print("Public key (publish this):  \(pair.publicKey)")
    print("Private key (keep this secret, never commit it):  \(pair.privateKey)")

case "sign":
    guard args.count >= 3 else { fail("cynapse sign <bank.json> <private-key-file>") }
    do {
        let url = URL(fileURLWithPath: args[1])
        let key = try String(contentsOfFile: args[2], encoding: .utf8)
        let signature = try BankSignature.sign(Data(contentsOf: url), privateKey: key)
        try Data((signature + "\n").utf8).write(to: url.appendingPathExtension("sig"))
        print("Wrote \(url.lastPathComponent).sig")
    } catch { fail("\(error)") }

case "demo":
    guard args.count >= 3, let behaviour = StubBehaviour(rawValue: args[2]) else {
        fail("cynapse demo <bank.json> <\(StubBehaviour.allCases.map(\.rawValue).joined(separator: "|"))> [--full]")
    }
    let bank = loadBank(args[1])
    let model = StubModel(behaviour, bank: bank)
    let runner = Runner(bank: bank, model: model)
    let mode: RunMode = full ? .full : .quick
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let records = try await runner.run(mode)
            let profile = ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: mode,
                                               baseline: runner.baseline, createdAt: Date())
            summary(profile)
        } catch { fail("\(error)") }
        semaphore.signal()
    }
    semaphore.wait()

case "score":
    guard args.count >= 3 else { fail("cynapse score <bank.json> <transcript.jsonl>") }
    let bank = loadBank(args[1])
    let records = Runner.readTranscript(URL(fileURLWithPath: args[2]))
    guard !records.isEmpty else { fail("No answers found in \(args[2]).") }
    let runner = Runner(bank: bank, model: StubModel(.honest, bank: bank))
    let mode: RunMode = full ? .full : .quick
    let profile = ProfileBuilder.build(records: records, bank: bank,
                                       model: ModelIdentity(name: "from transcript", provider: "unknown"),
                                       mode: mode, baseline: runner.baseline, createdAt: Date())
    printJSON(profile)

case "fingerprint":
    guard args.count >= 2 else { fail("cynapse fingerprint <model-folder>") }
    do {
        let (hash, size) = try ModelFingerprint.sha256(ofFolder: URL(fileURLWithPath: args[1]))
        print("\(hash)  (\(size) bytes)")
    } catch { fail("\(error)") }

case "pool-commit", "pool-verify":
    guard args.count >= 2 else { fail("cynapse \(command) <pool.json>") }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let pool = try JSONDecoder().decode(Pool.self, from: data)
        let hash = Pool.fingerprint(data)
        var register = (try? JSONDecoder().decode(PoolRegister.self, from: Data(contentsOf: registerURL))) ?? PoolRegister(pools: [])
        if command == "pool-commit" {
            register.pools.removeAll { $0.id == pool.pool.id }
            register.pools.append(.init(id: pool.pool.id, sha256: hash, created: pool.pool.created, retires: pool.pool.retires, released: false))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(register).write(to: registerURL)
            print("Pool \(pool.pool.id): \(pool.items.count) items, sha256 \(hash)")
            print("Recorded in Bank/pools.json. Publish that file now; keep the pool itself private until it retires on \(pool.pool.retires).")
        } else {
            guard let entry = register.pools.first(where: { $0.id == pool.pool.id }) else { fail("No published fingerprint for pool \(pool.pool.id).") }
            print(entry.sha256 == hash ? "Matches: this is the pool whose fingerprint was published." : "Does NOT match the published fingerprint.")
            if entry.sha256 != hash { exit(1) }
        }
    } catch { fail("\(error)") }

case "run":
    guard args.count >= 4 else { fail("cynapse run <bank.json> <apple|anthropic:model|openai:model|gemini:model> <out-dir> [--full]") }
    var bank = loadBank(args[1])
    if let poolPath {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: poolPath))
            let pool = try JSONDecoder().decode(Pool.self, from: data)
            let seed = UInt64(Date().timeIntervalSince1970 / 86400)
            bank = bank.drawing(poolDraw, from: pool, fingerprint: Pool.fingerprint(data), seed: seed)
            print("Drawing \(bank.pool?.drawn.count ?? 0) unpublished questions from pool \(pool.pool.id).")
        } catch { fail("Couldn't read the pool: \(error)") }
    }
    let spec = args[2]
    let model: any CheckedModel
    if spec == "apple" {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { fail("Apple's on-device model needs macOS 26 or later.") }
        let availability = AppleModel.availability
        guard availability.available else { fail(availability.reason ?? "Apple Intelligence isn't available.") }
        model = AppleModel()
        #else
        fail("This build has no FoundationModels.")
        #endif
    } else {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = CloudModel.Provider(rawValue: parts[0]) else { fail("Unknown model \(spec).") }
        guard let key = ProcessInfo.processInfo.environment[provider.environmentKey], !key.isEmpty else {
            fail("Set \(provider.environmentKey) to your own key.")
        }
        model = CloudModel(provider: provider, model: parts[1], key: key)
    }
    let out = URL(fileURLWithPath: args[3], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let safe = model.identity.name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
    let base = out.appendingPathComponent(String(safe))
    let runner = Runner(bank: bank, model: model, transcriptURL: base.appendingPathExtension("modelcheck.transcript.jsonl"))
    let mode: RunMode = full ? .full : .quick
    runner.onEvent = { event in
        switch event {
        case .answered(_, let index, let total):
            FileHandle.standardError.write(Data("\r  \(index) of \(total)".utf8))
        case .scored(let outcome, let plain):
            FileHandle.standardError.write(Data("\r  \(outcome.itemId): \(plain)\n".utf8))
        case .confirming(let item, let condition):
            FileHandle.standardError.write(Data("\r  Asking \(item) again (\(condition))\n".utf8))
        default: break
        }
    }
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let profile = try await runner.check(mode)
            try profile.jsonData().write(to: base.appendingPathExtension("modelcheck.json"))
            print("")
            summary(profile)
            print("\nWrote \(base.lastPathComponent).modelcheck.json and its transcript to \(out.path)")
        } catch { fail("\(error)") }
        semaphore.signal()
    }
    semaphore.wait()

default:
    fail("Unknown command \(command).")
}
