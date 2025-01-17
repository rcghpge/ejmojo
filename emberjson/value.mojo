from .object import Object
from .array import Array
from .utils import *
from utils import Variant
from .constants import *
from .traits import JsonValue, PrettyPrintable
from collections import InlineArray
from utils import StringSlice
from memory import UnsafePointer
from .simd import *
from sys.intrinsics import unlikely, likely
from .parser import Parser
from .format_int import write_int
from sys.intrinsics import _type_is_eq


@value
@register_passable("trivial")
struct Null(JsonValue):
    @always_inline
    fn __eq__(self, n: Null) -> Bool:
        return True

    @always_inline
    fn __ne__(self, n: Null) -> Bool:
        return False

    @always_inline
    fn __str__(self) -> String:
        return "null"

    @always_inline
    fn __repr__(self) -> String:
        return self.__str__()

    @always_inline
    fn min_size_for_string(self) -> Int:
        return 4

    @always_inline
    fn __bool__(self) -> Bool:
        return False

    @always_inline
    fn __as_bool__(self) -> Bool:
        return False

    @always_inline
    fn write_to[W: Writer](self, mut writer: W):
        writer.write(self.__str__())


fn constrain_json_type[T: CollectionElement]():
    alias valid = _type_is_eq[T, Int]() or _type_is_eq[T, Float64]() or _type_is_eq[T, String]() or _type_is_eq[
        T, Bool
    ]() or _type_is_eq[T, Object]() or _type_is_eq[T, Array]() or _type_is_eq[T, Null]()
    constrained[valid, "Invalid type for JSON"]()


@value
struct Value(JsonValue):
    alias Type = Variant[Int, Float64, String, Bool, Object, Array, Null]
    var _data: Self.Type

    @always_inline
    fn __init__(out self):
        self._data = Null()

    @implicit
    @always_inline
    fn __init__(out self, owned v: Self.Type):
        self._data = v^

    @implicit
    fn __init__(out self, owned j: JSON):
        if j.is_object():
            self._data = j.object()
        else:
            self._data = j.array()

    @implicit
    @always_inline
    fn __init__(out self, v: Int):
        self._data = v

    @implicit
    @always_inline
    fn __init__(out self, v: Float64):
        self._data = v

    @implicit
    @always_inline
    fn __init__(out self, owned v: Object):
        self._data = v^

    @implicit
    @always_inline
    fn __init__(out self, owned v: Array):
        self._data = v^

    @implicit
    @always_inline
    fn __init__(out self, owned v: String):
        self._data = v^

    @implicit
    @always_inline
    fn __init__(out self, owned v: StringLiteral):
        self._data = String(v)

    @implicit
    @always_inline
    fn __init__(out self, v: Null):
        self._data = v

    @implicit
    @always_inline
    fn __init__(out self, v: Bool):
        self._data = v

    @always_inline
    fn __copyinit__(out self, other: Self):
        self._data = other._data

    @always_inline
    fn __moveinit__(out self, owned other: Self):
        self._data = other._data^

    fn __eq__(self, other: Self) -> Bool:
        if self._data._get_discr() != other._data._get_discr():
            return False

        if self.isa[Int]() and other.isa[Int]():
            return self.int() == other.int()
        elif self.isa[Float64]() and other.isa[Float64]():
            return self.float() == other.float()
        elif self.isa[String]() and other.isa[String]():
            return self.string() == other.string()
        elif self.isa[Bool]() and other.isa[Bool]():
            return self.bool() == other.bool()
        elif self.isa[Object]() and other.isa[Object]():
            return self.object() == other.object()
        elif self.isa[Array]() and other.isa[Array]():
            return self.array() == other.array()
        return False

    @always_inline
    fn __ne__(self, other: Self) -> Bool:
        return not self == other

    fn __bool__(self) -> Bool:
        if self.isa[Int]():
            return Bool(self.int())
        elif self.isa[Float64]():
            return Bool(self.float())
        elif self.isa[String]():
            return Bool(self.string())
        elif self.isa[Bool]():
            return self.bool()
        elif self.isa[Null]():
            return False
        elif self.isa[Object]():
            return Bool(self.object())
        return Bool(self.array())

    fn __as_bool__(self) -> Bool:
        return Bool(self)

    @always_inline
    fn isa[T: CollectionElement](self) -> Bool:
        constrain_json_type[T]()
        return self._data.isa[T]()

    @always_inline
    fn __getitem__[T: CollectionElement](self) -> ref [self._data] T:
        constrain_json_type[T]()
        return self._data[T]

    @always_inline
    fn get[T: CollectionElement](self) -> ref [self._data] T:
        constrain_json_type[T]()
        return self._data[T]

    @always_inline
    fn int(self) -> Int:
        return self._data[Int]

    @always_inline
    fn null(self) -> Null:
        return Null()

    @always_inline
    fn string(self) -> ref [self._data] String:
        return self._data[String]

    @always_inline
    fn float(self) -> Float64:
        return self._data[Float64]

    @always_inline
    fn bool(self) -> Bool:
        return self._data[Bool]

    @always_inline
    fn object(self) -> ref [self._data] Object:
        return self._data[Object]

    @always_inline
    fn array(self) -> ref [self._data] Array:
        return self._data[Array]

    fn write_to[W: Writer](self, mut writer: W):
        if self.isa[Int]():
            write_int(self.int(), writer)
        elif self.isa[Float64]():
            writer.write(self.float())
        elif self.isa[String]():
            writer.write('"')
            writer.write(self.string())
            writer.write('"')
        elif self.isa[Bool]():
            writer.write("true") if self.bool() else writer.write("false")
        elif self.isa[Null]():
            writer.write("null")
        elif self.isa[Object]():
            writer.write(self.object())
        elif self.isa[Array]():
            writer.write(self.array())

    fn _pretty_to_as_element[W: Writer](self, mut writer: W, indent: String, curr_depth: Int):
        if self.isa[Object]():
            writer.write("{\n")
            self.object()._pretty_write_items(writer, indent, curr_depth + 1)
            writer.write(indent * curr_depth, "}")
        elif self.isa[Array]():
            writer.write("[\n")
            self.array()._pretty_write_items(writer, indent, curr_depth + 1)
            writer.write(indent * curr_depth, "]")
        else:
            self.write_to(writer)

    fn pretty_to[W: Writer](self, mut writer: W, indent: String, *, curr_depth: Int = 0):
        if self.isa[Object]():
            self.object().pretty_to(writer, indent, curr_depth=curr_depth)
        elif self.isa[Array]():
            self.array().pretty_to(writer, indent, curr_depth=curr_depth)
        else:
            self.write_to(writer)

    fn min_size_for_string(self) -> Int:
        if self.isa[Int]():
            return 10
        elif self.isa[Float64]():
            return 10
        elif self.isa[String]():
            return len(self.string()) + 2  # include the surrounding quotes
        elif self.isa[Bool]():
            return 4 if self.bool() else 5
        elif self.isa[Null]():
            return Null().min_size_for_string()
        elif self.isa[Object]():
            return self.object().min_size_for_string()
        elif self.isa[Array]():
            return self.array().min_size_for_string()

        return 0

    @always_inline
    fn __str__(self) -> String:
        return write(self)

    @always_inline
    fn __repr__(self) -> String:
        return self.__str__()

    @staticmethod
    @always_inline
    fn from_string(out v: Value, input: String) raises:
        var p = Parser(input)
        v = p.parse_value()
