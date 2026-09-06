from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple, TypedDict, Union

import sys


class AssemblerError(Exception):
    def __init__(self, filename: str, line: int, column: Optional[int], message: str) -> None:
        super().__init__(message)
        self.filename = filename
        self.line = line
        self.column = column
        self.message = message

    def __str__(self) -> str:
        location = f"{self.filename}:{self.line}"
        if self.column is not None:
            location += f":{self.column}"
        return f"{location}: {self.message}"


@dataclass
class Token:
    kind: str
    text: str
    file: str
    line: int
    column: int
    value: Optional[Union[int, str]] = None

    def describe(self) -> str:
        return self.text


def token_error(token: Token, message: str) -> None:
    raise AssemblerError(token.file, token.line, token.column, message)


def general_error(filename: str, line: int, column: Optional[int], message: str) -> None:
    raise AssemblerError(filename, line, column, message)


ESCAPE_SEQUENCES: Dict[str, str] = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "0": "\0",
    "'": "'",
    '"': '"',
    "\\": "\\",
}


def strip_comment(line: str) -> str:
    result: List[str] = []
    quote: Optional[str] = None
    escaped = False
    for ch in line:
        if quote:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            result.append(ch)
            continue
        if ch in (";", "#"):
            break
        result.append(ch)
    return "".join(result)


class Tokenizer:
    def __init__(self, filename: str) -> None:
        self.filename = filename

    def tokenize(self, lines: Sequence[str]) -> List[Tuple[int, List[Token]]]:
        result: List[Tuple[int, List[Token]]] = []
        for idx, raw_line in enumerate(lines, 1):
            line = strip_comment(raw_line.rstrip("\n"))
            tokens = self._tokenize_line(line, idx)
            result.append((idx, tokens))
        return result

    def _tokenize_line(self, text: str, line_no: int) -> List[Token]:
        tokens: List[Token] = []
        i = 0
        length = len(text)
        while i < length:
            ch = text[i]
            if ch.isspace():
                i += 1
                continue
            col = i + 1
            if ch.isalpha() or ch == "_":
                start = i
                i += 1
                while i < length and (text[i].isalnum() or text[i] == "_"):
                    i += 1
                word = text[start:i]
                tokens.append(Token("IDENT", word, self.filename, line_no, col))
                continue
            if ch.isdigit():
                token, i = self._lex_number(text, line_no, i)
                tokens.append(token)
                continue
            if ch == "'":
                token, i = self._lex_char(text, line_no, i)
                tokens.append(token)
                continue
            if ch == '"':
                token, i = self._lex_string(text, line_no, i)
                tokens.append(token)
                continue
            single_char_tokens = {
                ":": "COLON",
                ",": "COMMA",
                "(": "LPAREN",
                ")": "RPAREN",
                "%": "PERCENT",
                "+": "PLUS",
                "-": "MINUS",
                "!": "BANG",
            }
            if ch in single_char_tokens:
                tokens.append(Token(single_char_tokens[ch], ch, self.filename, line_no, col))
                i += 1
                continue
            general_error(self.filename, line_no, col, f"unexpected character '{ch}'")
        return tokens

    def _lex_number(self, text: str, line_no: int, start: int) -> Tuple[Token, int]:
        col = start + 1
        i = start
        length = len(text)
        base = 10
        if text[i] == "0" and i + 1 < length and text[i + 1].lower() in "boxd":
            prefix = text[i + 1].lower()
            base = {"b": 2, "o": 8, "d": 10, "x": 16}[prefix]
            i += 2
            digit_start = i
            while i < length and self._is_digit(text[i], base):
                i += 1
            if digit_start == i:
                general_error(self.filename, line_no, col, "numeric literal missing digits")
            digits = text[digit_start:i]
            value = int(digits, base)
            token_text = text[start:i]
            return Token("NUMBER", token_text, self.filename, line_no, col, value), i
        digit_start = i
        while i < length and text[i].isdigit():
            i += 1
        digits = text[digit_start:i]
        value = int(digits, 10)
        token_text = text[start:i]
        return Token("NUMBER", token_text, self.filename, line_no, col, value), i

    @staticmethod
    def _is_digit(ch: str, base: int) -> bool:
        if base == 2:
            return ch in "01"
        if base == 8:
            return ch >= "0" and ch <= "7"
        if base == 10:
            return ch.isdigit()
        if base == 16:
            lower = ch.lower()
            return lower.isdigit() or ("a" <= lower <= "f")
        return False

    def _lex_char(self, text: str, line_no: int, start: int) -> Tuple[Token, int]:
        i = start + 1
        length = len(text)
        chars: List[str] = []
        escaped = False
        while i < length:
            ch = text[i]
            if escaped:
                chars.append(self._translate_escape(ch, line_no, i + 1))
                escaped = False
            else:
                if ch == "\\":
                    escaped = True
                elif ch == "'":
                    i += 1
                    if len(chars) != 1:
                        general_error(self.filename, line_no, start + 1, "character literal must contain exactly one character")
                    value = ord(chars[0])
                    token_text = text[start:i]
                    return Token("CHAR", token_text, self.filename, line_no, start + 1, value), i
                else:
                    chars.append(ch)
            i += 1
        general_error(self.filename, line_no, start + 1, "unterminated character literal")
        raise AssertionError("unreachable")

    def _lex_string(self, text: str, line_no: int, start: int) -> Tuple[Token, int]:
        i = start + 1
        length = len(text)
        chars: List[str] = []
        escaped = False
        while i < length:
            ch = text[i]
            if escaped:
                chars.append(self._translate_escape(ch, line_no, i + 1))
                escaped = False
            else:
                if ch == "\\":
                    escaped = True
                elif ch == '"':
                    i += 1
                    token_text = text[start:i]
                    value = "".join(chars)
                    return Token("STRING", token_text, self.filename, line_no, start + 1, value), i
                else:
                    chars.append(ch)
            i += 1
        general_error(self.filename, line_no, start + 1, "unterminated string literal")
        raise AssertionError("unreachable")

    def _translate_escape(self, ch: str, line_no: int, column: int) -> str:
        if ch in ESCAPE_SEQUENCES:
            return ESCAPE_SEQUENCES[ch]
        general_error(self.filename, line_no, column, f"unknown escape '\\{ch}'")
        raise AssertionError("unreachable")


@dataclass
class Operand:
    tokens: List[Token]
    _expr: Optional[Expr] = field(default=None, init=False, repr=False)

    def as_expr(self) -> Expr:
        if not self.tokens:
            general_error(self.tokens[0].file if self.tokens else "<unknown>", self.tokens[0].line if self.tokens else 0, None, "missing expression")
        if self._expr is None:
            parser = ExpressionParser(self.tokens)
            self._expr = parser.parse()
        return self._expr

    def first_token(self) -> Token:
        if not self.tokens:
            general_error("<unknown>", 0, None, "missing operand")
        return self.tokens[0]

    def expect_single_token(self, kind: str, description: str) -> Token:
        if len(self.tokens) != 1 or self.tokens[0].kind != kind:
            token_error(self.first_token(), f"{description} must be a {kind.lower()} literal")
        return self.tokens[0]


@dataclass
class Instruction:
    mnemonic: str
    token: Token
    operands: List[Operand]


@dataclass
class Directive:
    name: str
    token: Token
    operands: List[Operand]


@dataclass
class Statement:
    labels: List[Token]
    body: Optional[Union[Directive, Instruction]]
    line: int
    address: Optional[int] = None


@dataclass
class Expr:
    token: Token


@dataclass
class NumberExpr(Expr):
    value: int


@dataclass
class SymbolExpr(Expr):
    name: str


@dataclass
class UnaryExpr(Expr):
    op: str
    operand: Expr


@dataclass
class BinaryExpr(Expr):
    op: str
    left: Expr
    right: Expr


@dataclass
class FuncExpr(Expr):
    func: str
    argument: Expr


class ExpressionParser:
    def __init__(self, tokens: Sequence[Token]) -> None:
        self.tokens = tokens
        self.pos = 0

    def parse(self) -> Expr:
        expr = self._parse_expr()
        if self._peek() is not None:
            token = self._peek()
            assert token is not None
            token_error(token, "unexpected token in expression")
        return expr

    def _parse_expr(self) -> Expr:
        node = self._parse_unary()
        while True:
            tok = self._peek()
            if tok and tok.kind in ("PLUS", "MINUS"):
                self.pos += 1
                right = self._parse_unary()
                node = BinaryExpr(token=tok, op=tok.text, left=node, right=right)
            else:
                break
        return node

    def _parse_unary(self) -> Expr:
        tok = self._peek()
        if tok and tok.kind in ("PLUS", "MINUS"):
            self.pos += 1
            operand = self._parse_unary()
            return UnaryExpr(token=tok, op=tok.text, operand=operand)
        return self._parse_primary()

    def _parse_primary(self) -> Expr:
        tok = self._peek()
        if tok is None:
             raise AssemblerError("<unknown>", 0, None, "incomplete expression")
        if tok.kind == "NUMBER":
            self.pos += 1
            assert isinstance(tok.value, int)
            return NumberExpr(token=tok, value=int(tok.value))
        if tok.kind == "CHAR":
            self.pos += 1
            assert isinstance(tok.value, int)
            return NumberExpr(token=tok, value=int(tok.value))
        if tok.kind == "IDENT":
            self.pos += 1
            return SymbolExpr(token=tok, name=tok.text)
        if tok.kind == "LPAREN":
            self.pos += 1
            expr = self._parse_expr()
            self._expect("RPAREN")
            return expr
        if tok.kind == "PERCENT":
            return self._parse_percent_function()
        token_error(tok, "unexpected token in expression")
        raise AssertionError("unreachable")

    def _parse_percent_function(self) -> Expr:
        percent_tok = self._expect("PERCENT")
        ident = self._expect("IDENT")
        func_name = ident.text.lower()
        if func_name not in {"hi", "lo", "rel"}:
            token_error(ident, f"unknown function %{ident.text}")
        self._expect("LPAREN")
        arg = self._parse_expr()
        self._expect("RPAREN")
        return FuncExpr(token=percent_tok, func=func_name, argument=arg)

    def _peek(self) -> Optional[Token]:
        if self.pos >= len(self.tokens):
            return None
        return self.tokens[self.pos]

    def _expect(self, kind: str) -> Token:
        tok = self._peek()
        if tok is None or tok.kind != kind:
            if tok is None:
                general_error("<unknown>", 0, None, f"expected {kind.lower()}")
            token_error(tok, f"expected {kind.lower()}")
        self.pos += 1
        return tok


SymbolTable = Dict[str, int]


def evaluate_expression(expr: Expr, symbols: SymbolTable, ctx_addr: int) -> int:
    if isinstance(expr, NumberExpr):
        return int(expr.value)
    if isinstance(expr, SymbolExpr):
        if expr.name not in symbols:
            token_error(expr.token, f"undefined symbol '{expr.name}'")
        return symbols[expr.name]
    if isinstance(expr, UnaryExpr):
        value = evaluate_expression(expr.operand, symbols, ctx_addr)
        if expr.op == "+":
            return value
        if expr.op == "-":
            return -value
    if isinstance(expr, BinaryExpr):
        left = evaluate_expression(expr.left, symbols, ctx_addr)
        right = evaluate_expression(expr.right, symbols, ctx_addr)
        if expr.op == "+":
            return left + right
        if expr.op == "-":
            return left - right
    if isinstance(expr, FuncExpr):
        value = evaluate_expression(expr.argument, symbols, ctx_addr)
        if expr.func == "hi":
            return (value >> 8) & 0xFF
        if expr.func == "lo":
            return value & 0xFF
        if expr.func == "rel":
            return value - ctx_addr
    token_error(expr.token, "invalid expression")
    return 0


DIRECTIVES = {"org", "db", "dh", "dw", "char", "string", "equ"}
INSTRUCTIONS = {
    "EXT",
    "ADD",
    "SUB",
    "ADDC",
    "SUBC",
    "AND",
    "OR",
    "XOR",
    "LSH",
    "ASH",
    "LI",
    "ADDI",
    "LD",
    "ST",
    "BR",
    "B",
}


def parse_operands(tokens: Sequence[Token]) -> List[Operand]:
    operands: List[Operand] = []
    current: List[Token] = []
    last_was_comma = False
    for tok in tokens:
        if tok.kind == "COMMA":
            if not current:
                token_error(tok, "missing operand before comma")
            operands.append(Operand(list(current)))
            current.clear()
            last_was_comma = True
            continue
        current.append(tok)
        last_was_comma = False
    if last_was_comma:
        token_error(tokens[-1], "dangling comma")
    if current:
        operands.append(Operand(list(current)))
    return operands


def parse_statements(tokens_per_line: List[Tuple[int, List[Token]]]) -> List[Statement]:
    statements: List[Statement] = []
    for line_no, tokens in tokens_per_line:
        idx = 0
        labels: List[Token] = []
        while idx + 1 < len(tokens) and tokens[idx].kind == "IDENT" and tokens[idx + 1].kind == "COLON":
            labels.append(tokens[idx])
            idx += 2
        if idx >= len(tokens):
            if labels:
                statements.append(Statement(labels=labels, body=None, line=line_no))
            continue
        token = tokens[idx]
        if token.kind != "IDENT":
            token_error(token, "expected opcode or directive")
        name_raw = token.text
        idx += 1
        operands = parse_operands(tokens[idx:])
        name_lower = name_raw.lower()
        name_upper = name_raw.upper()
        body: Optional[Union[Directive, Instruction]]
        if name_lower in DIRECTIVES:
            body = Directive(name=name_lower, token=token, operands=operands)
        elif name_upper in INSTRUCTIONS:
            body = Instruction(mnemonic=name_upper, token=token, operands=operands)
        else:
            token_error(token, f"unknown directive or opcode '{name_raw}'")
        statements.append(Statement(labels=labels, body=body, line=line_no))
    return statements


class MemoryImage:
    def __init__(self) -> None:
        self.data = bytearray()
        self.written: Set[int] = set()

    def write_byte(self, addr: int, value: int, token: Token) -> None:
        if value < 0 or value > 0xFF:
            token_error(token, f"value {value} out of byte range [0..255]")
        if addr < 0:
            token_error(token, f"negative address 0x{addr:X}")
        if addr in self.written:
            token_error(token, f"address 0x{addr:04X} already written")
        if addr >= len(self.data):
            self.data.extend(b"\x00" * (addr + 1 - len(self.data)))
        self.data[addr] = value
        self.written.add(addr)

    def write_bytes(self, addr: int, values: Iterable[int], token: Token) -> None:
        for offset, value in enumerate(values):
            self.write_byte(addr + offset, value, token)

    def write_word(self, addr: int, word: int, token: Token) -> None:
        self.write_bytes(addr, [(word >> 8) & 0xFF, word & 0xFF], token)

    def to_bytes(self) -> bytes:
        return bytes(self.data)


class RrrSpec(TypedDict):
    opcode: int


RRR_SPECS: Dict[str, RrrSpec] = {
    "ADD": {"opcode": 0x1},
    "SUB": {"opcode": 0x2},
    "ADDC": {"opcode": 0x3},
    "SUBC": {"opcode": 0x4},
    "AND": {"opcode": 0x5},
    "OR": {"opcode": 0x6},
    "XOR": {"opcode": 0x7},
}

SHIFT_SPECS: Dict[str, int] = {"LSH": 0x8, "ASH": 0x9}

REGISTER_ALIASES: Dict[str, int] = {"zero": 0, "flag": 1, "hpt": 2, "lpt": 3}

CONDITION_CODES: Dict[str, int] = {
    "!carry": 0,
    "carry": 1,
    "!zero": 2,
    "zero": 3,
    "even": 4,
    "odd": 5,
    "!sign": 6,
    "sign": 7,
    "!overflow": 8,
    "overflow": 9,
    "false": 14,
    "true": 15,
}


def parse_register(operand: Operand, description: str) -> int:
    if len(operand.tokens) != 1 or operand.tokens[0].kind != "IDENT":
        token_error(operand.first_token(), f"{description} must be a register")
    name = operand.tokens[0].text.lower()
    if name in REGISTER_ALIASES:
        return REGISTER_ALIASES[name]
    if name.startswith("r") and name[1:].isdigit():
        idx = int(name[1:])
        if 0 <= idx <= 15:
            return idx
    token_error(operand.tokens[0], f"invalid register '{operand.tokens[0].text}'")
    return 0


def parse_condition(operand: Operand, symbols: SymbolTable, ctx_addr: int) -> int:
    tokens = operand.tokens
    if len(tokens) == 1:
        tok = tokens[0]
        if tok.kind == "IDENT":
            name = tok.text.lower()
            if name in CONDITION_CODES:
                return CONDITION_CODES[name]
        if tok.kind == "NUMBER":
            assert isinstance(tok.value, int)
            value = int(tok.value)
            if 0 <= value <= 15:
                return value
            token_error(tok, "condition code out of range [0..15]")
    if len(tokens) == 2 and tokens[0].kind == "BANG" and tokens[1].kind == "IDENT":
        name = "!" + tokens[1].text.lower()
        if name in CONDITION_CODES:
            return CONDITION_CODES[name]
        token_error(tokens[1], f"invalid condition '!{tokens[1].text}'")
    expr = operand.as_expr()
    value = evaluate_expression(expr, symbols, ctx_addr)
    if 0 <= value <= 15:
        return value
    token_error(operand.first_token(), "condition code out of range [0..15]")
    return 0


def require_operand_count(token: Token, operands: Sequence[Operand], expected: int) -> None:
    if len(operands) != expected:
        token_error(token, f"{token.text} expects {expected} operand(s), got {len(operands)}")


def encode_unsigned(value: int, bits: int, token: Token, description: str) -> int:
    max_value = (1 << bits) - 1
    if not (0 <= value <= max_value):
        token_error(token, f"{description} out of range [0..{max_value}]")
    return value


def encode_signed(value: int, bits: int, token: Token, description: str) -> int:
    min_value = -(1 << (bits - 1))
    max_value = (1 << (bits - 1)) - 1
    if not (min_value <= value <= max_value):
        token_error(token, f"{description} out of range [{min_value}..{max_value}]")
    mask = (1 << bits) - 1
    return value & mask


def encode_as_needed(value: int, bits: int, token: Token, description: str) -> int:
    if value < 0:
        return encode_signed(value, bits, token, description)
    else:
        return encode_unsigned(value, bits, token, description)


def encode_instruction(instr: Instruction, symbols: SymbolTable, ctx_addr: int) -> int:
    mnem = instr.mnemonic
    ops = instr.operands
    if mnem == "EXT":
        require_operand_count(instr.token, ops, 1)
        expr = ops[0].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        imm = encode_unsigned(value, 12, ops[0].first_token(), "immediate")
        return imm
    if mnem in RRR_SPECS:
        require_operand_count(instr.token, ops, 3)
        rdest = parse_register(ops[0], "destination register")
        rsrc1 = parse_register(ops[1], "source register")
        rsrc2 = parse_register(ops[2], "source register")
        opcode = RRR_SPECS[mnem]["opcode"]
        return (opcode << 12) | (rdest << 8) | (rsrc1 << 4) | rsrc2
    if mnem in SHIFT_SPECS:
        require_operand_count(instr.token, ops, 3)
        rdest = parse_register(ops[0], "destination register")
        rsrc = parse_register(ops[1], "source register")
        expr = ops[2].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        imm = encode_signed(value, 4, ops[2].first_token(), "shift amount")
        opcode = SHIFT_SPECS[mnem]
        return (opcode << 12) | (rdest << 8) | (rsrc << 4) | imm
    if mnem == "LI":
        require_operand_count(instr.token, ops, 2)
        reg = parse_register(ops[0], "destination register")
        expr = ops[1].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        if not (-128 <= value <= 255):
            token_error(ops[1].first_token(), "immediate out of range [-128..255]")
        imm = value & 0xFF
        return (0xA << 12) | (reg << 8) | imm
    if mnem == "ADDI":
        require_operand_count(instr.token, ops, 3)
        rdest = parse_register(ops[0], "destination register")
        rsrc = parse_register(ops[1], "source register")
        expr = ops[2].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        if -8 <= value <= 7:
            imm = value & 0xF
        elif 0 <= value <= 15:
            imm = value
        else:
            token_error(ops[2].first_token(), "immediate out of range [-8..7] or [0..15]")
        return (0xB << 12) | (rdest << 8) | (rsrc << 4) | imm
    if mnem == "LD":
        require_operand_count(instr.token, ops, 2)
        reg = parse_register(ops[0], "destination register")
        expr = ops[1].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        imm = encode_signed(value, 8, ops[1].first_token(), "immediate")
        return (0xC << 12) | (reg << 8) | imm
    if mnem == "ST":
        require_operand_count(instr.token, ops, 2)
        reg = parse_register(ops[0], "source register")
        expr = ops[1].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        imm8 = encode_signed(value, 8, ops[1].first_token(), "immediate")
        high = (imm8 >> 4) & 0xF
        low = imm8 & 0xF
        return (0xD << 12) | (high << 8) | (reg << 4) | low
    if mnem == "BR":
        require_operand_count(instr.token, ops, 2)
        cond = parse_condition(ops[0], symbols, ctx_addr)
        expr = ops[1].as_expr()
        value = evaluate_expression(expr, symbols, ctx_addr)
        imm = encode_signed(value, 8, ops[1].first_token(), "immediate")
        return (0xE << 12) | (cond << 8) | imm
    if mnem == "B":
        require_operand_count(instr.token, ops, 3)
        cond = parse_condition(ops[0], symbols, ctx_addr)
        r1 = parse_register(ops[1], "left register")
        r2 = parse_register(ops[2], "right register")
        return (0xF << 12) | (cond << 8) | (r1 << 4) | r2
    token_error(instr.token, f"unsupported instruction '{instr.mnemonic}'")
    return 0


def first_pass(statements: List[Statement]) -> SymbolTable:
    symbols: SymbolTable = {}
    label_tokens: Dict[str, Token] = {}
    location = 0
    for stmt in statements:
        body = stmt.body
        if isinstance(body, Instruction) and location % 2 != 0:
            location += 1
        stmt.address = location
        for label in stmt.labels:
            name = label.text
            if name in symbols:
                prev = label_tokens[name]
                token_error(label, f"label '{name}' redefined (previously at line {prev.line})")
            symbols[name] = location
            label_tokens[name] = label
        if body is None:
            continue
        if isinstance(body, Directive):
            location = process_directive_pass1(body, location, symbols)
        else:
            if location % 2 != 0:
                token_error(body.token, f"misaligned instruction at address 0x{location:04X}")
            location += 2
    return symbols


def process_directive_pass1(directive: Directive, location: int, symbols: SymbolTable) -> int:
    name = directive.name
    operands = directive.operands
    if name == "org":
        require_operand_count(directive.token, operands, 1)
        expr = operands[0].as_expr()
        value = evaluate_expression(expr, symbols, location)
        if value < 0:
            token_error(operands[0].first_token(), "org address must be non-negative")
        return value
    if name == "db":
        return location + len(operands)
    if name == "dh":
        return location + 2 * len(operands)
    if name == "dw":
        return location + 4 * len(operands)
    if name == "char":
        for operand in operands:
            operand.expect_single_token("CHAR", "char directive")
        return location + len(operands)
    if name == "string":
        total = 0
        for operand in operands:
            token = operand.expect_single_token("STRING", "string directive")
            assert isinstance(token.value, str)
            total += len(token.value)
        return location + total
    if name == "equ":
        require_operand_count(directive.token, operands, 2)
        return location
    token_error(directive.token, f"unknown directive '{directive.name}'")
    return location


def constants_pass(statements: List[Statement], symbols: SymbolTable) -> SymbolTable:
    for stmt in statements:
        body = stmt.body
        if isinstance(body, Directive):
            process_directive_constants_pass(body, stmt.address, symbols)
    return symbols


def process_directive_constants_pass(directive: Directive, location: int, symbols: SymbolTable) -> None:
    name = directive.name
    operands = directive.operands
    if name == "equ":
        if len(operands[0].tokens) != 1 or operands[0].tokens[0].kind != "IDENT":
            token_error(operands[0].first_token(), f"Constant name must be an identifier")
        constant_name = operands[0].tokens[0].text
        expr = operands[1].as_expr()
        if constant_name in symbols:
            token_error(constant_name, f"constant '{constant_name}' redefines existing symbol")
        symbols[constant_name] = evaluate_expression(expr, symbols, location)


def second_pass(statements: List[Statement], symbols: SymbolTable) -> bytes:
    image = MemoryImage()
    for stmt in statements:
        addr = stmt.address if stmt.address is not None else 0
        body = stmt.body
        if body is None:
            continue
        if isinstance(body, Directive):
            process_directive_pass2(body, addr, symbols, image)
        else:
            if addr % 2 != 0:
                token_error(body.token, f"misaligned instruction at address 0x{addr:04X}")
            word = encode_instruction(body, symbols, addr)
            image.write_word(addr, word, body.token)
    return image.to_bytes()


def process_directive_pass2(directive: Directive, address: int, symbols: SymbolTable, image: MemoryImage) -> None:
    name = directive.name
    operands = directive.operands
    if name == "org":
        expr = operands[0].as_expr()
        value = evaluate_expression(expr, symbols, address)
        if value < 0:
            token_error(operands[0].first_token(), "org address must be non-negative")
        return
    if name == "db":
        current = address
        for operand in operands:
            expr = operand.as_expr()
            value = evaluate_expression(expr, symbols, current)
            value = encode_as_needed(value, 8, operand.first_token(), "byte")
            image.write_byte(current, value, operand.first_token())
            current += 1
        return
    if name == "dh":
        current = address
        for operand in operands:
            expr = operand.as_expr()
            value = evaluate_expression(expr, symbols, current)
            value = encode_as_needed(value, 16, operand.first_token(), "halfword")
            image.write_bytes(current, [(value >> 8) & 0xFF, value & 0xFF], operand.first_token())
            current += 2
        return
    if name == "dw":
        current = address
        for operand in operands:
            expr = operand.as_expr()
            value = evaluate_expression(expr, symbols, current)
            value = encode_as_needed(value, 32, operand.first_token(), "word")
            bytes_ = [
                (value >> 24) & 0xFF,
                (value >> 16) & 0xFF,
                (value >> 8) & 0xFF,
                value & 0xFF,
            ]
            image.write_bytes(current, bytes_, operand.first_token())
            current += 4
        return
    if name == "char":
        current = address
        for operand in operands:
            token = operand.expect_single_token("CHAR", "char directive")
            assert isinstance(token.value, int)
            image.write_byte(current, token.value, token)
            current += 1
        return
    if name == "string":
        current = address
        for operand in operands:
            token = operand.expect_single_token("STRING", "string directive")
            assert isinstance(token.value, str)
            for ch in token.value:
                code = ord(ch)
                if code > 0xFF:
                    token_error(token, "string literal contains non-ASCII character")
                image.write_byte(current, code, token)
                current += 1
        return
    if name == "equ":
        return
    token_error(directive.token, f"unknown directive '{directive.name}'")


def bytes_to_hex_lines(data: bytes) -> List[str]:
    buffer = bytearray(data)
    if len(buffer) % 2 == 1:
        buffer.append(0)
    lines: List[str] = []
    for i in range(0, len(buffer), 1):
        word = buffer[i]
        lines.append(f"{word:02X}")
    return lines


def read_source(path: Path) -> List[Statement]:
    text = path.read_text(encoding="utf-8").splitlines()
    tokenizer = Tokenizer(str(path))
    tokens_per_line = tokenizer.tokenize(text)
    return parse_statements(tokens_per_line)


def write_hex_file(path: Path, data: bytes) -> None:
    lines = bytes_to_hex_lines(data)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for line in lines:
            handle.write(line + "\n")


def assemble(source_path: Path, output_path: Path) -> None:
    statements = read_source(source_path)
    symbols = first_pass(statements)
    symbols = constants_pass(statements, symbols)
    image = second_pass(statements, symbols)
    write_hex_file(output_path, image)


def main() -> None:
    parser = argparse.ArgumentParser(description="Assemble source into .hex")
    parser.add_argument("source", help="input assembly file")
    parser.add_argument("-o", "--output", required=True, help="output .hex file")
    args = parser.parse_args()
    source_path = Path(args.source)
    output_path = Path(args.output)
    try:
        assemble(source_path, output_path)
    except AssemblerError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"I/O error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()