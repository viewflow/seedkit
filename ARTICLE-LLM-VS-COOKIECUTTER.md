# Can an LLM generate your Django project boilerplate?

*Suggested Reddit title: "Can an LLM generate your Django project boilerplate? Several weeks of trying, and everything the model broke along the way."*

---

Here is how I think starting a Django project should work.

You type one sentence: "Job board. Postgres, Google login, background tasks, Stripe, deploy to my VPS." A few minutes later there's a project. Your packages, wired together, dev/prod settings split, CI, server boots.

Can an AI actually do that? I spent several weeks finding out. I set up a test: one AI would build the project from a single sentence, and a second AI—acting as an independent reviewer—would check the work. After fixing over 200 bugs, here are the main ways the AI failed:

**Outdated APIs.** Code libraries change, but the model doesn't know about the updates. The model used old code to connect Stripe. It used a version from two updates ago. Everything looked finished, but payment confirmations never arrived.

**"Improved" snippets.** One simplified line in the admin setup, and user passwords started saving as plain text. The site ran, all tests passed. The bug surfaced only when someone saved a user through the admin—and that user could no longer log in.

**Insecure defaults.** Without an obvious production target, the model shipped its development settings untouched—debug mode on, the host check wide open, a throwaway secret key committed straight to the repo—with no warning that any of it was unsafe to deploy.

**Conflicting files.** The AI would write settings in one file that completely broke another, or schedule a background task pointing to code it never even wrote. Each file looked fine on its own, but together, the project was broken.

**Too many add-ons to remember.** Django isn't batteries-included anymore: accounts, tasks, email, storage—ten to fifteen third-party choices in a real project. Asked in prose to "figure out what's needed," the model quietly dropped whole categories, and you'd only notice when the feature that depended on one turned up missing.

Even the newest AI models make the same mistakes—they just hide them better. Their knowledge still has an end date, and that problem never goes away. And anyway, I don't want to waste my expensive AI subscription just to write basic code. I don't need a super-smart AI to write standard templates; I just need the knowledge to sit outside the model.

This is why I built [seedkit](https://github.com/RobustaRush/seedkit)—a plugin for coding assistants like Cursor and Claude Code. Instead of relying on the AI's memory, it gives the AI small, focused cheat sheets linking to official docs. It forces the AI to look up current versions instead of guessing. A fresh, independent AI checks the work, which caught almost every bug I mentioned above. The reference files hold the actual knowledge; the AI just acts as a fast typist. Now, a cheap and fast AI can reliably handle the boring setup work, saving your expensive AI limits for the complex code only you can write.

Unlike traditional code generators, an AI doesn't give you the exact same result every time you ask. To make sure the skill really works, I created a continuous practice loop. The AI would generate a project, check it for mistakes, and figure out how to avoid those mistakes in the future. I repeated this cycle over and over — more rounds than I'd like to perform — to refine the instructions. Then, to prove these improvements were real, I compared the results against a 'control group'—I gave the exact same prompts to a basic AI without any of my special instructions to see how it performed on its own. Giving instructions to an AI isn't free. If you give it too much text to read, it gets confused and starts getting things wrong. So every line of instruction had to earn its place—the reference files kept getting shorter.

**Try it:** `/plugin marketplace add RobustaRush/seedkit`, then `/seedkit` in an empty directory. Generated examples with audit logs live in [seedkit-examples](https://github.com/RobustaRush/seedkit-examples). There's also a `/seedkit-slim` variant with no reference files (raw model knowledge) if you want to compare the two approaches yourself.

---

# LinkedIn teaser (~120 words)

Can an AI actually write your Django boilerplate?

I spent several weeks finding out. I set up a test: one AI would build the project from a single sentence, and a second AI—acting as an independent reviewer—would check the work. After fixing over 200 bugs, here are the main ways the AI failed:

— Outdated APIs: Code libraries change, but the model doesn't know about the updates.
— "Improved" snippets: It simplifies code and accidentally introduces critical bugs.
— Insecure defaults: It leaves dangerous security holes without printing a single warning.
— Conflicting files: It writes settings in one file that completely break another.

To fix this, I built an AI skill. I wanted to be absolutely sure it works. These days, the internet is flooded with untested AI skills. I put mine through a continuous self-improving loop: the AI would generate a project, catch its own mistakes, and refine its instructions over and over. I even ran it against a control group, starting completely fresh with zero 'agent memory', to prove the improvements are real and that it works for everyone—not just on my machine.

Full story: [link to the article]
The tool (open source): github.com/RobustaRush/seedkit

#django #python #llm
