# Backlog

Each file is one GitHub issue: the first line is the title, the `Labels:` line the labels, the rest the body.
Once the repo is on GitHub, publish them all with:

```sh
for f in issues/[0-9]*.md; do
  gh issue create --title "$(head -1 "$f" | sed 's/^# //')" \
    --label "$(sed -n 's/^Labels: //p' "$f")" \
    --body "$(sed '1,/^Labels:/d' "$f")"
done
```
