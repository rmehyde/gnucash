def pretty_print(text):
    indent = 0
    result = []
    in_paren = False

    for char in text:
        if char == '(':
            if in_paren:
                result.append('\n' + '  ' * indent)
            result.append(char)
            indent += 1
            in_paren = True
        elif char == ')':
            indent -= 1
            result.append(char)
            if indent > 0:
                result.append('\n' + '  ' * indent)
            in_paren = False
        elif char == ' ' and result and result[-1] in ['(', '\n']:
            continue
        else:
            result.append(char)

    # Join result and reformat to ensure closing parentheses are on the same line
    formatted_result = ''.join(result)
    formatted_lines = []
    for line in formatted_result.split('\n'):
        formatted_line = line.rstrip()
        if formatted_line.endswith(')'):
            formatted_lines.append(formatted_line)
        else:
            formatted_lines.append(formatted_line)

    return '\n'.join(formatted_lines)


# def pretty_print(text, indent=3):
#     cur_indent = ""
#     cur_line = 0
#     line_of_last_indent = -1
#     result = []
#
#     for char in text:
#         if char == "(":
#             cur_indent += " " * indent
#             line_of_last_indent = cur_line
#         elif char == ")":
#             if cur_line != line_of_last_indent:
#                 cur_indent = cur_indent[:-indent]
#
#         result.append(char)
#         if char == "\n":
#             result += cur_indent
#             cur_line += 1


with open("/home/reese/.local/share/gnucash/report-debug.log") as f:
    nested_text = f.read()
formatted_text = pretty_print(nested_text)
print(formatted_text)
