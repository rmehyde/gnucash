def pretty_print(text, indent=2):
    cur_indent = ""
    cur_line = 0
    line_of_indent_stack = []
    result = []

    for char in text:
        if char == "(":
            result.append("\n" + cur_indent)
            cur_line += 1
            line_of_indent_stack.append(cur_line)
            cur_indent += " " * indent
        elif char == ")":
            cur_indent = cur_indent[:-indent]
            try:
                line_of_indent = line_of_indent_stack.pop()
            except IndexError:
                line_of_indent = None

            if cur_line != line_of_indent:
                result.append("\n" + cur_indent)

        result.append(char)

        if char == "\n":
            result += cur_indent
            cur_line += 1

    return "".join(result)


with open("/home/reese/.local/share/gnucash/report-debug.log") as f:
    nested_text = f.read()
formatted_text = pretty_print(nested_text)
print(formatted_text)
with open("accounts-list.txt", 'w') as f:
    f.write(formatted_text)
