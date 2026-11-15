# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

An abapGit project, developed off-stack, with two goals:
1. Provide an ABAP utility (the "abapGit auto pusher") that automatically syncs recent developments to a shared development branch. It is meant to run daily in the SAP system.
2. Serve as a worked example of building ABAP off-stack with an AI agent, then pulling it into a real ABAP system through abapGit.

It assumes the full abapGit package is already installed in the target system, so the code may call abapGit's own classes and APIs.

## Development model (no local build/test)

- There's no ABAP runtime, compiler, linter or test runner in this repo. Code is written here as abapGit-serialized files, committed, and then **pulled into an SAP system with abapGit**. That pull is where activation, syntax checks and ABAP Unit happen.
- So no local build or test commands exist. Check code carefully for syntax and object validity before committing, because errors only show up after the pull.

## ABAP conventions

- **Target release: SAP NetWeaver 7.50.** Use only syntax available there. Inline declarations, `NEW`, `VALUE`, `CONV`, `COND`/`SWITCH`, string templates and host variables (`@`) in Open SQL are fine. Don't use newer constructs such as `ENUM` types (7.51+), `FINAL(...)` inline declarations or other post-7.50 features. Forks for other releases are expected to change this section.
- **Respect object-name length limits.** The README calls this out as a common pitfall. Examples: classes and interfaces max 30 characters, DDIC tables 16, function groups 26, message classes 20. Use the customer namespace (`Z`/`Y`) prefix.
- Follow the abapGit serialization layout. Object files go under the source folder named in `.abapgit.xml`, with lowercase filenames such as `zcl_name.clas.abap` + `zcl_name.clas.xml` or `zname.prog.abap` + `zname.prog.xml`. Every object needs its matching `.xml` metadata file, or abapGit won't deserialize it.
