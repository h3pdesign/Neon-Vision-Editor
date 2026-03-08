# Claude Export Fixture 2

## Mixed Narrative and Snippets

The next block contains markdown-like content that should remain stable while scrolling and editing.

### Checklist

- [x] Keep headings stable
- [x] Keep code fences stable
- [x] Keep list indentation stable
- [ ] Ensure no invisible mutation on save

#### Pseudo transcript

User: "Can you generate a deployment plan?"
Assistant: "Yes, here is a plan with phases."

~~~bash
set -euo pipefail
for file in *.md; do
  echo "checking ${file}"
  rg -n "TODO|FIXME" "$file" || true
done
~~~

### Stress text

Words_with_underscores should not be interpreted as markdown emphasis when they are plain identifiers.

`a_b_c` `x_y_z` __double__ **strong** *single* _single_

> Block quote line 1
> Block quote line 2

Final paragraph with punctuation: (alpha), [beta], {gamma}, <delta>.
