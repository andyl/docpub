# Specled Lite

Posted 2026 Apr 08 Wed for Discord readers - I'll remove this content after a
week or so.

After reading Mike Hostetler's "Specled" initiative, I hacked my own "Spec Led"
system.  This is quick and dirty!  At some point probably I'll migrate to
Mike's system.  But so far I find my quick-hack approach very useful.  Over the
last month I've used this spec-led in a half-dozen projects - never going back.

Both of the 'commands' in this directory should be put into the
~/.claude/commands directory.  

It's a two part system:
1) `/gen-feat` - create a feature specification
2) `/gen-plan` - create an implemenation plan 

For step 1), sometimes I write a one-paragraph design right in the claude TUI.
Sometimes I write a design file, then tell claude "/gen-feat @MyDesignFile"

I store the specs in the project repo, and check them into git using this
directory structure:

```
_spec/
  designs/
    YYMMDD_<design_doc>.md
    ...
  features/
    YYMMDD_<feature spec>.md
    ...
  plans/
    YYMMDD_<implementation plan>.md
    ...
```

I have got into the habit of prefixing the _spec files with YYMMDD so I know
the order in which they were created.
