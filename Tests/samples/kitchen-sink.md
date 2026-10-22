# Markdown Preview

A **fast**, *native* Quick Look preview with ~~no~~ zero background cost.
Inline `code`, <kbd>⌘</kbd> + <kbd>Space</kbd>, and a [link](https://example.com).
Autolink: https://github.com and www.apple.com. Emoji stay as text: 🚀 ✅ — “quotes” & ampersands.

## Lists

- Item one
- Item two
  - Nested *a*
  - Nested **b**
    1. Deep ordered
    2. Second
- [ ] Task to do
- [x] Task done

1. First
2. Second

   Loose paragraph inside an item.
3. Third

## Code

```swift
let greeting = "Hello, <world> & \"friends\""
print(greeting)
```

    indented code block

## Table

| Left | Center | Right |
|:-----|:------:|------:|
| a    |   b    |     c |
| `x`  | **y**  |   1.5 |
| long cell with text | z | 42 |

## Quotes and alerts

> A plain blockquote
> spanning two lines.

> [!NOTE]
> Useful information.

> [!TIP]
> Helpful advice.

> [!IMPORTANT]
> Key information.

> [!WARNING]
> Urgent info.

> [!CAUTION]
> Risky stuff.

> [!NOTE] this is not an alert because text is on the same line

## Footnotes

Here is a footnote reference[^1] and another[^note].

[^1]: The first footnote.
[^note]: A named footnote.

## Images

![Local image](images/dot.png)
![Image with space](<images/my dot.png>)
![Percent encoded](images/my%20dot.png "with a title")
![Missing](images/nope.png)
![Remote image](https://example.com/badge.svg)
<img src="images/dot.png" width="32" alt="raw html image">

## HTML

<details>
<summary>Click to expand</summary>

Hidden *markdown* content.

</details>

<script>alert("this must not run")</script>
<style>body{background:red!important}</style>

Text with a <mark>highlight</mark> and H<sub>2</sub>O and x<sup>2</sup>.

---

Escapes: \*not emphasis\*, 5 < 6 > 4, AT&T, &copy; &#169;.

Hard break with two spaces  
next line.

###### Small heading
