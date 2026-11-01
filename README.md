# Open Training — multi-user LMS starter

Neutral, GitHub Pages compatible LMS with Supabase Auth, Postgres, Row Level Security, role management, course authoring, manual quizzes, PowerPoint text-to-lessons import, assignments, attempt tracking and CSV reporting. **This is an implementation starter, not an audited production LMS.**

## Setup

1. Create a new **Supabase** project. From **SQL Editor**, run `supabase/schema.sql`. Configure email confirmation and allowed redirect URLs under Authentication > URL Configuration to include your published GitHub Pages URL.
2. Register the first user at the site after configuring the frontend. Promote them using the **Supabase SQL editor** (trusted administrative access): `update public.profiles set role='system_admin' where email='YOUR_EMAIL';` Sign out/in afterward.
3. Copy `config.example.js` to `config.js`, and fill in Supabase project URL and **publishable/anon** key. Never include a service-role key. This key is public and safe for frontend use only when RLS is correctly configured.
4. Create an empty GitHub repository, e.g. `open-training-lms`. Upload `index.html`, `styles.css`, `app.js`, `config.example.js`, `config.js`, `.gitignore`, `README.md`, and `supabase/schema.sql` to its root. `config.js` contains public environment configuration, and GitHub's web upload ignores no files based on `.gitignore`; check what you upload. GitHub Pages cannot run backend code, so Supabase provides it.
5. Enable GitHub Pages > Deploy from branch > `main` > `/ (root)`.

**Note:** `config.js` is excluded by `.gitignore` for normal git pushes. For GitHub Pages, use a deploy workflow that generates `config.js` from GitHub Actions variables, or explicitly include `config.js` as a public file. Its publishable key is public, but **never store private keys**. To create a local demo, make the config.js file before opening on a local HTTP server.

## Roles

- **System administrator:** all course and role management plus reports.
- **Training administrator:** author any course, publish and assign to learner accounts, view reports.
- **Instructor:** author their own courses, publish and assign their own courses; access reporting of relevant courses.
- **Learner:** browse published catalog, study assigned courses, mark lessons complete, take assigned assessments.

Default registration is `learner`. Only `system_admin` can promote/demote roles through app. Server-side Row Level Security and restricted RPC protect the data. The quiz-answer key is withheld from learner reads and scored on the database server.

## PowerPoint import

Uses JSZip in the browser to extract text from each `.pptx` slide and create editable lessons. Displays a **text-based slide preview**, not a pixel-faithful PowerPoint rendering. Images, embedded video, animations, presenter notes, and full layouts are not preserved. Manual quiz authoring is supported, but **AI quiz generation, narration, and complete slide fidelity have not been implemented**. Text-based quiz draft generation without professional review is not appropriate for safety-sensitive learning.

## Important limitations and pre-production work

- **No organization/tenant isolation**: this starter is one organization/workspace. Don't onboard unrelated clients or organizations until tenant IDs and tenant-scoped RLS are implemented.
- **No attached PowerPoint files in shared storage**: source files are locally parsed and discarded. Implement private Supabase Storage policies and storage quotas if retaining slides, images, PDFs or audio is required.
- **Not compliance-ready**: implement durable certificates with verification links, secure audit events, course versioning, retake policies, minimum passing thresholds per course, completion rules enforced by the backend, testing, accessibility reviews, and data retention/privacy policies.
- **Course editing is replacement-based**, so editing a published course replaces its lesson/question records and invalidates prior lesson completion foreign keys; implement versioned course releases for a production system.
- **Quiz completion** tracks independent passes/attempts. It is possible to submit the assessment before completing lessons; completion screen requires both but the database does not enforce a certificate of record.
- **Instructor report visibility**: currently all staff can select learner profiles and completion/attempt rows. For organizations with sensitive user records, scope reporting to assigned courses and enforce policy there.
- Need QA against your actual Supabase project and GitHub Pages deployment, especially concurrent edits, account invites, file importing, and security tests. The JavaScript syntax check is not an integration test.

## Run locally

Create config.js; run `python3 -m http.server 8000` inside the repository directory. Visit `http://localhost:8000` (add it to Supabase authorized redirect URLs).