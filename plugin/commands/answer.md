---
description: Driving mode — deliver the answer to the work just finished as a message of its own, headline pushed to the phone first, so the user hears the answer without the working notes. Claude queues this on itself through Herdr at the end of a working turn; it is rarely typed.
---

# /answer — the answer, on its own

The turn before this one did the work, and its notes are the record the user can replay later. This message is the one they will play now.

Write the answer to that work, following the Driving style:

- What was done or found, and what it means for the user. Lead with the outcome.
- If an agent has not come back yet, what is still running and where. When nothing is running, say nothing about it.
- Any question last, as yes or no or a choice between two things.

First, before writing, send the headline as a push notification with the `PushNotification` tool (load it through tool search if it is deferred): the answer's first sentence, under 200 characters, one line, no markdown. The user asked for one per answer while driving, because Siri reads it aloud through CarPlay or AirPods with no tap. The phone skips it when the user is at the terminal; that is fine.

Then write the answer. Make no other tool calls. Do not repeat the working notes or describe the steps unless a step is the point. If the work did not finish, say so first and say why.
