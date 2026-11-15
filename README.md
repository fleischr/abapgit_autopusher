# abapGit Auto Pusher

The purpose of this abapGit project is two-fold

1. To provide teams with a utility that automatically syncs all of the recent developments to a given shared development branch
2. To offer an example of building ABAP programs off-stack with abapGit, leveraging AI agents

Overall - this can help introduce basic pipeline for agentic ABAP developments. This project by itself serves as a kind of working introduction on how off-stack ABAP developments can work their way up into an actual ABAP development system.

## Using the abapGit auto pusher

Requirements:
- Have the full abapGit package cloned into your system 
- Your syntax version may differ by system. Feel free to fork this repo, change the CLAUDE.md 

## Understanding how the abapGit autoPusher was built using Claude Code

### Step 0 : Git init and The baseline claude.md settings
Depending on your release level (whether older or newer) you can direct Claude to have a certain kind of ABAP Development style. For this repo - Claude was instructed to use syntax compatible with netweaver 7.5 (which should be representative of a mix of oldish and newish ABAP coding styles deployed today)
### Step 1 : Drafting a basic plan
### Step 2 : Refining an improved plan with plan mode
### Step 3 : Your agent builds the report
### Step 4 : Pull the abapGit auto pusher to your system
### Step 5 : Run the abapGit auto pusher daily. 

## Common pitfalls
Settings in claude.md can sometimes miss character-length restriction of ABAP object names. 