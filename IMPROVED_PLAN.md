# abapGit Auto Pusher – Improved Plan

This plan refines `BASIC_PLAN.md` into something an agent can build from directly. The original requirements stay in place, and the gaps are filled: architecture, abapGit API reuse, unattended operation, safety on a shared branch, and verification.

## 1. Goal and scope

Build one executable report, `ZABAPGIT_AUTOPUSH`, that pushes all local changes in one abapGit online repository to a given branch. It must:

- run interactively (SE38/SA38) and as an unattended **daily background job** (SM36)
- use only syntax available on **SAP NetWeaver 7.50** (see `CLAUDE.md`)
- reuse the abapGit classes already installed in the system instead of re-implementing Git or HTTP logic

**Out of scope:** pulling, merging, conflict resolution, creating or linking abapGit repositories, and pushing several repositories in one run (schedule one job step per repo instead).

## 2. Corrections and clarifications to the basic plan

| Basic plan | Improved plan |
|---|---|
| "se38 program" | Executable report (program type 1), runnable from SE38/SA38 and SM36 |
| "John Smit", "Commiter", "yourcommpany.com" | "John Smith", "Committer", "jsmith@yourcompany.com" |
| "current system timestamp" (format not defined) | System date and time (`sy-datum` / `sy-uzeit`), formatted `YYYY-MM-DD HH:MM:SS` |
| "executing user id of the is ABAP report" | `sy-uname` of the user running the report (in background, the job step user) |
| Repo URL and ABAP package are independent inputs | Both must resolve to the **same** abapGit repo, otherwise the run aborts. This guards against pushing the wrong package |
| "push all current changes" | Push all local **additions and modifications**. Files that exist only in Git are **never deleted**, only reported (see §5, step 4) |
| No dry-run | A test-mode checkbox, on by default, lists what would be pushed without pushing |

## 3. Deliverables (abapGit-serialized files)

| File | Purpose |
|---|---|
| `.abapgit.xml` | Repo settings: starting folder `/src/`, folder logic `PREFIX`, main language `E` |
| `src/package.devc.xml` | Package `ZABAPGIT_AUTOPUSH`. Rename per system if needed (max 30 characters) |
| `src/zabapgit_autopush.prog.abap` | Report source |
| `src/zabapgit_autopush.prog.xml` | Program attributes (type 1), **selection texts** and **text symbols** |

Design rules:
- All logic lives in a local class `lcl_autopush` inside the report, so the deliverable is a single repository object with no extra global classes.
- Name lengths: the program name is 17 characters (limit 40), the package 17 (limit 30), and every selection-screen parameter is at most 8 characters.
- Every user-facing text goes in text symbols or selection texts, not hard-coded literals.

## 4. Selection screen

| Block | Parameter | Type | Notes |
|---|---|---|---|
| Repository | `p_url` | CHAR 255, LOWER CASE, OBLIGATORY | GitHub HTTPS URL of the repo |
| | `p_pack` | `devclass`, OBLIGATORY | Package linked to the repo in abapGit |
| | `p_branch` | CHAR 100, LOWER CASE, OBLIGATORY | `dev` or `refs/heads/dev`. The `refs/heads/` prefix is added if missing |
| Authentication | `p_user` | CHAR 100, LOWER CASE, OBLIGATORY | GitHub user id |
| | `p_token` | CHAR 255, LOWER CASE, OBLIGATORY | Personal access token. Masked (see below) |
| Commit | `p_name` | CHAR 100, LOWER CASE, OBLIGATORY | Committer name, e.g. "John Smith" |
| | `p_email` | CHAR 100, LOWER CASE, OBLIGATORY | Committer email |
| | `p_msg` | CHAR 255, LOWER CASE, OBLIGATORY | Defaults to `Automated Backup &timestamp by &user` in `INITIALIZATION` |
| Options | `p_test` | CHECKBOX, DEFAULT 'X' | Test mode: list changes, don't push |

**Token masking:** in `AT SELECTION-SCREEN OUTPUT`, loop over `SCREEN` and set `screen-invisible = 1` for `P_TOKEN`, so input appears as `*****`.

## 5. Processing flow

`START-OF-SELECTION` creates `lcl_autopush` and calls `run( )`. All steps run inside one `TRY ... CATCH zcx_abapgit_exception`.

1. **Validate inputs** (`validate`)
   - `p_url` starts with `https://`.
   - `p_email` matches a basic `x@y.z` pattern (`FIND REGEX`).
   - The package exists (TDEVC).
   - Look up the repo with `zcl_abapgit_repo_srv=>get_instance( )->get_repo_from_url( EXPORTING iv_url = ... IMPORTING ei_repo = ... ev_reason = ... )`. If `ei_repo` is initial, abort with `ev_reason`.
   - Cast to `zif_abapgit_repo_online`. Abort if it's an offline repo.
   - Abort if the repo's package (`get_package( )`) ≠ `p_pack`.

2. **Log in** (`set_login`)
   - Call `zcl_abapgit_login_manager=>set_basic( iv_uri = <repo url> iv_username = p_user iv_password = p_token )`. This is the same mechanism `zcl_abapgit_background` uses for its background jobs, so abapGit never shows a login popup.

3. **Select the branch** (`switch_branch`)
   - Normalize `p_branch` to `refs/heads/<name>`.
   - Remember `get_selected_branch( )` as the original branch.
   - If it differs, call `select_branch( <target> )` and then `check_for_valid_branch( )`. A non-existent branch aborts the run. The branch is not created.

4. **Collect and stage changes** (`stage_changes`)
   - Get `zcl_abapgit_stage_logic=>get_stage_logic( )->get( <repo> )`, which returns `local` and `remote` file lists.
   - For each `local` entry, call `lo_stage->add( iv_path iv_filename iv_data )`, the same calls `zcl_abapgit_background_push_fi->push_fixed` makes.
   - **Don't** call `lo_stage->rm` for `remote` entries. Collect them into a "remote-only, not deleted, review manually" list. This keeps the job from deleting work other developers pushed to the shared branch.
   - If nothing was staged, write "Nothing to push", skip the push and finish normally. Never create an empty commit.

5. **Build the commit** (`build_comment`)
   - Copy `p_msg`, then `REPLACE ALL OCCURRENCES OF '&timestamp' ...` with `YYYY-MM-DD HH:MM:SS` and `'&user'` with `sy-uname`.
   - Append a blank line, then a sorted, de-duplicated list of `<OBJ_TYPE> <OBJ_NAME>` for each staged object, modeled on `build_comment` in `zcl_abapgit_background_push_fi`.
   - Fill `zif_abapgit_git_definitions=>ty_comment`: `committer-name`/`-email` and `author-name`/`-email` from `p_name`/`p_email`, `comment` from the built text.

6. **Push** (`push`)
   - If `p_test` is set, list the staged objects and stop.
   - Otherwise call `<repo_online>->push( is_comment = ls_comment io_stage = lo_stage )`.

7. **Clean up (always)**
   - On success and on error: if the branch was switched, `select_branch( <original> )`, then `zcl_abapgit_login_manager=>clear( )`.
   - Implement with a local result flag: catch the exception, run the cleanup, then report the error. A failure during cleanup is also reported, not swallowed.

8. **Output and error reporting**
   - Write a list with `WRITE` (in background it goes to the job spool): repo URL, package, target branch, test or live mode, staged objects, the remote-only list, and the final result (commit pushed / nothing to push / error text).
   - On error in **background** (`sy-batch = 'X'`): `MESSAGE ... TYPE 'E'`, so the job ends as **cancelled** and shows up in SM37 monitoring.
   - On error in **dialog**: show the list, then `MESSAGE ... TYPE 'S' DISPLAY LIKE 'E'`.

## 6. Daily scheduling

1. Run the report once in SE38 with `p_test` on, and check the list.
2. Save a **variant** with `p_test` off. In the variant attributes, set the token field to **Protect field** and **Hide field**.
3. In SM36, create a daily job with one step: `ZABAPGIT_AUTOPUSH` with that variant. The step user needs abapGit authorization and read access to the package.
4. Don't schedule it at the same time as an abapGit background job (`ZABAPGIT` background mode) on the same repo.

**Token security:**
- The variant hides and protects the token on screen, but its value is stored **unencrypted** in table VARI. Restrict access to variant maintenance and table VARI.
- Use a fine-grained GitHub token with write access to repository contents for **this repository only**, and set an expiry date.
- Rotate the token by editing the variant.

## 7. abapGit version compatibility

abapGit's internal API changes between releases. For example, newer builds push through `zcl_abapgit_repo_factory=>get_repo_push( <repo> )->push( ... )` instead of `zif_abapgit_repo_online->push`, and stage and login method signatures have changed over time. Before writing or pulling the report:

- Open `ZCL_ABAPGIT_BACKGROUND_PUSH_FI` and `ZCL_ABAPGIT_BACKGROUND` in the **installed** abapGit, and mirror the exact calls they use for staging, the comment, push and login.
- If the developer edition of abapGit (the full package) isn't installed, the report can't compile. The standalone `ZABAPGIT` program doesn't expose these classes globally.

## 8. Verification (in the SAP system after the abapGit pull)

| # | Check | Expected |
|---|---|---|
| 1 | Activate the program; run syntax check and extended check (SLIN) | No errors |
| 2 | Test mode against a test repo and branch | Listed objects match the abapGit stage screen for that repo |
| 3 | Live push to a scratch branch | Commit visible on GitHub with the given author/committer, placeholders replaced, object list in the body |
| 4 | Repo linked to `main`, push to `dev` | After the run the repo is linked to `main` again |
| 5 | Same as 4 with a wrong token | Error reported, repo still linked to `main`, login cleared |
| 6 | File present only in Git | Not deleted, listed under "remote-only" |
| 7 | No local changes | "Nothing to push", no commit created |
| 8 | Wrong package for the URL, offline repo, non-existent branch | Run aborts with a clear message before any push |
| 9 | SM36 job with the variant | Job finishes, spool shows the result. The token isn't visible in the variant display |
