# gh-lab

One command to start a RAIK183H lab.

```
gh extension install raik183h-labs/gh-lab
```

Then, from the folder where you keep your course work:

```
gh lab lab-loops-1
```

It asks for your partner's GitHub username, sets up your team's repository,
downloads the code, and opens it in your editor. Safe to run again any time — if
you close your terminal or come back the next day, run the same command.

## Choosing your editor

By default it opens whichever editor it finds, Cursor first and then VS Code.
To pin it to one:

```
gh lab --ide vscode
gh lab --ide cursor
gh lab --ide auto     # go back to picking on its own
```

The choice is saved in your global git config (`raik.ide`), so it is the same in
Terminal and in Git Bash, and it survives reinstalling the extension. Run
`gh lab --ide` with nothing after it to see what is in effect right now.

## If something goes wrong

```
gh lab --check
```

Prints your setup and marks anything broken in red. Show that output to your
instructor or a TA.

Full setup and troubleshooting instructions are in the course guide.
