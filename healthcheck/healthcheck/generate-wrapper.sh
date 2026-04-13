#!/bin/bash
# Generates Wrapper.kt (no-op EWrapper implementation) from EWrapper.java
# Usage: generate-wrapper.sh <EWrapper.java path> <output Wrapper.kt path>
set -e

EWRAPPER_FILE="$1"
OUTPUT_FILE="$2"

if [ ! -f "$EWRAPPER_FILE" ]; then
    echo "Error: EWrapper.java not found at $EWRAPPER_FILE"
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Extract method signatures from EWrapper.java and convert to Kotlin no-op stubs
# 1. Join multi-line method signatures into single lines
# 2. Extract method declarations (lines ending with ;)
# 3. Convert Java types to Kotlin types
# 4. Generate override fun ... {} stubs

python3 -c "
import re, sys

with open('$EWRAPPER_FILE') as f:
    content = f.read()

# Remove comments
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r'//.*', '', content)

# Join multi-line method signatures
content = re.sub(r'\n\s+', ' ', content)

# Extract method signatures
methods = re.findall(r'(void|int|double|long|boolean|String)\s+(\w+)\s*\(([^)]*)\)\s*;', content)

type_map = {
    'int': 'Int', 'long': 'Long', 'double': 'Double',
    'boolean': 'Boolean', 'void': 'Unit', 'String': 'String?',
}

def convert_type(java_type):
    java_type = java_type.strip()
    if java_type in type_map:
        return type_map[java_type]
    if java_type.endswith('[]'):
        base = java_type[:-2]
        return f'Array<out {convert_type(base).rstrip(\"?\")}>?'
    if java_type.startswith('Set<'):
        return 'Mutable' + java_type + '?'
    if java_type.startswith('List<'):
        return 'Mutable' + java_type + '?'
    if java_type.startswith('Map<'):
        inner = java_type[4:-1]
        # Handle Map<Integer, Entry<String, Character>>
        return f'MutableMap<{inner}>?'.replace('Integer', 'Int').replace('Character', 'Char')
    return java_type + '?'

def convert_param(param):
    param = param.strip()
    if not param:
        return ''
    # Handle generic types like Map<Integer, Entry<String, Character>>
    # Split on last space that's not inside angle brackets
    depth = 0
    last_space = -1
    for i, c in enumerate(param):
        if c == '<': depth += 1
        elif c == '>': depth -= 1
        elif c == ' ' and depth == 0: last_space = i
    if last_space == -1:
        return param
    java_type = param[:last_space].strip()
    name = param[last_space+1:].strip()
    kotlin_type = convert_type(java_type)
    return f'{name}: {kotlin_type}'

lines = []
for ret_type, name, params in methods:
    if not params.strip():
        lines.append(f'    override fun {name}() {{}}')
    else:
        # Split params carefully (respecting generics)
        param_list = []
        depth = 0
        current = ''
        for c in params:
            if c == '<': depth += 1
            elif c == '>': depth -= 1
            elif c == ',' and depth == 0:
                param_list.append(current)
                current = ''
                continue
            current += c
        if current.strip():
            param_list.append(current)
        kotlin_params = ', '.join(convert_param(p) for p in param_list)
        lines.append(f'    override fun {name}({kotlin_params}) {{}}')

output = '''package com.manhinhang.ibgatewaydocker.healthcheck

import com.ib.client.*
import com.ib.client.protobuf.*

class Wrapper : EWrapper {
''' + chr(10).join(lines) + '''
}
'''

with open('$OUTPUT_FILE', 'w') as f:
    f.write(output)

print(f'Generated Wrapper.kt with {len(lines)} methods')
"
