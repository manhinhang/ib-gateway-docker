#!/bin/bash
# Generates Wrapper.kt from EWrapper.java. Most methods become no-op stubs;
# the error overloads are special-cased to capture the last error message
# into a `lastError` field so the healthcheck can detect IB-side failures
# instead of just "TCP socket open".
# Usage: generate-wrapper.sh <EWrapper.java path> <output Wrapper.kt path>
set -e

EWRAPPER_FILE="$1"
OUTPUT_FILE="$2"

if [ ! -f "$EWRAPPER_FILE" ]; then
    echo "Error: EWrapper.java not found at $EWRAPPER_FILE"
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

python3 -c "
import re

with open('$EWRAPPER_FILE') as f:
    content = f.read()

# Strip comments first.
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r'//.*', '', content)

# Join multi-line method signatures.
content = re.sub(r'\n\s+', ' ', content)

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
        return f'MutableMap<{inner}>?'.replace('Integer', 'Int').replace('Character', 'Char').replace('Entry<', 'MutableMap.MutableEntry<')
    return java_type + '?'

def split_params(params):
    if not params.strip():
        return []
    out, depth, current = [], 0, ''
    for c in params:
        if c == '<': depth += 1
        elif c == '>': depth -= 1
        elif c == ',' and depth == 0:
            out.append(current); current = ''; continue
        current += c
    if current.strip():
        out.append(current)
    return out

def parse_param(param):
    param = param.strip()
    if not param:
        return None, None
    depth, last_space = 0, -1
    for i, c in enumerate(param):
        if c == '<': depth += 1
        elif c == '>': depth -= 1
        elif c == ' ' and depth == 0: last_space = i
    if last_space == -1:
        return param, None
    java_type = param[:last_space].strip()
    name = param[last_space+1:].strip()
    return name, java_type

def build_error_body(parsed):
    '''parsed is a list of (name, java_type, kotlin_type) triples.'''
    by_name = {n: (jt, kt) for n, jt, kt in parsed}
    err_msg = 'errorMsg' if 'errorMsg' in by_name else None
    err_code = 'errorCode' if 'errorCode' in by_name else None
    exc_name = next((n for n, jt, kt in parsed if 'Exception' in jt or 'Throwable' in jt), None)
    str_name = next((n for n, jt, kt in parsed if jt == 'String'), None)
    if err_code and err_msg:
        return (
            '        if (' + err_code + ' in INFORMATIONAL_ERROR_CODES) return\n'
            '        lastError = \"[' + '\${' + err_code + '}] \${' + err_msg + '}\"'
        )
    if exc_name:
        return '        lastError = ' + exc_name + '?.message ?: ' + exc_name + '?.toString()'
    if str_name:
        return '        lastError = ' + str_name
    return '        // unrecognised error overload'

method_lines = []
for ret_type, name, params in methods:
    parsed = []
    for p in split_params(params):
        pname, ptype = parse_param(p)
        if pname is None:
            continue
        kt = convert_type(ptype) if ptype else ''
        parsed.append((pname, ptype, kt))
    kotlin_params = ', '.join(f'{pname}: {kt}' for pname, _, kt in parsed)

    if name == 'error':
        body = build_error_body(parsed)
        method_lines.append(f'    override fun {name}({kotlin_params}) {{\n{body}\n    }}')
    else:
        method_lines.append(f'    override fun {name}({kotlin_params}) {{}}')

output = '''package com.manhinhang.ibgatewaydocker.healthcheck

import com.ib.client.*
import com.ib.client.protobuf.*

/**
 * EWrapper implementation that captures the last error message reported by
 * the IB gateway via the error() callbacks. All other callbacks are no-ops.
 *
 * This file is GENERATED at build time from EWrapper.java by
 * generate-wrapper.sh. Do not edit by hand.
 */
class Wrapper : EWrapper {
    @Volatile
    var lastError: String? = null

    companion object {
        // 21xx codes are informational notices (data farm connection ok, etc.)
        // and 23xx are warnings, not failures. See IB API docs for full list.
        val INFORMATIONAL_ERROR_CODES = setOf(
            2104, 2106, 2107, 2108, 2110, 2119, 2137, 2150, 2157, 2158
        )
    }

''' + chr(10).join(method_lines) + '''
}
'''

with open('$OUTPUT_FILE', 'w') as f:
    f.write(output)

print(f'Generated Wrapper.kt with {len(method_lines)} methods')
"
