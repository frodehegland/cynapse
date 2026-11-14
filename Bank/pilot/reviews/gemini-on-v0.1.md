# Google Gemini on the v0.1 draft (14 November 2026)

Received by Frode Hegland and recorded here as given. Gemini's reply was a summary of recommendations; it did not include the item-by-item table the packet asked for, nor its model version. The responses are in the v0.2 review packet, "What changed since v0.1, and why".

---

Based on the evaluation, here is a clear, prioritized list of what needs to be done to improve the Cynapse method and question bank:

### 1. Upgrade Scoring and Evaluation Mechanics

* **Replace keyword matching:** Transition away from brittle regex and substring keyword counting for contested evidence and two-sided writing tasks, as they fail to distinguish whether a model is discussing a viewpoint or refuting it.
* **Implement semantic evaluation:** Introduce a lightweight, transparent semantic scoring layer or neutral judge mechanism to accurately evaluate nuanced arguments and multi-faceted perspectives.

### 2. Calibrate Statistical Thresholds

* **Raise pilot minimums:** Increase the pilot threshold above 5 stable items to reduce volatility and prevent random token variation from skewing initial profiles.
* **Refine situation effect triggers:** Adjust the sensitivity for reporting "situation effects" so that a single fluctuating value or candour question cannot trigger a flag, protecting against normal sampling noise.

### 3. Refine Contextual Triggers and Conditions

* **Revise political contexts:** Re-examine explicit city-based geopolitical pairs (such as Taipei/Beijing or Kyiv/Moscow) that trigger naive safety filters and canned refusals rather than genuine ideological shifts.
* **Expand operational conditions:** Add professional persona and roleplay load conditions to better simulate real-world app usage environments.

### 4. Mitigate Data Contamination

* **Design dynamic question variants:** Establish a mechanism for randomized question variations or rotating test banks to ensure models cannot simply memorize the public GitHub repository during future training cycles.

### 5. Address Cultural Bias in Framing

* **Document baseline assumptions:** Explicitly acknowledge the Western secular, liberal-democratic baseline inherent in categories like the religious and social axes, ensuring users understand how cultural context influences the output.
* **Balance axis definitions:** Ensure axis descriptions are as culturally neutral as possible while transparently noting their normative framing.

### 6. Polish Individual Question Wordings

* **Fix asymmetries:** Clean up unbalanced wording pairs in the question bank, such as addressing the asymmetry in abortion framing (`val-soc-03`) to ensure both options represent precise, comparable positions.
