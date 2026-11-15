# abapGit Auto Pusher

In this abapGit repo - Build an se38 program ```ZABAPGIT_AUTOPUSH``` that will automatically push all current abapGit changes to a given branch

Assume the full abapGit package has been cloned into the SAP system. Some utility classes are needed from there.
See https://github.com/abapGit/abapGit.git

Required inputs of the report

Repository 
- Repo URL
- ABAP Package
- Branch

Authentication
- Github user id
- Github token. The contents of this field must be obfuscated/password protected

Commit
- Committer name (ex: "John Smit")
- Commiter email (jsmith@yourcommpany.com)
- Commit message. Default to "Automated Backup &timestamp by &user". Before the commit is pushed - replace &timestamp with current system timestamp and &user with executing user id of the is ABAP report