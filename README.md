# convert_json

[![Package Version](https://img.shields.io/hexpm/v/convert_json)](https://hex.pm/packages/convert_json)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/convert_json/)

**Encode and decode JSON from and to Gleam types !**

Define a converter once and encode and decode as much as you want.

## Installation

```sh
gleam add convert
gleam add convert_json
```

## Usage

```gleam
import gleam/io
import gleam/json
import convert as c
import convert/json as cjson

pub type Person {
  Person(name: String, age: Int)
}

pub fn main() {
  let converter =
    c.object({
      use name <- c.field("name", fn(v: Person) { Ok(v.name) }, c.string())
      use age <- c.field("age", fn(v: Person) { Ok(v.age) }, c.int())
      c.success(Person(name:, age:))
    })

  Person("Anna", 21)
  |> cjson.json_encode(converter)
  |> json.to_string
  |> io.debug
  // '{"name": "Anna", "age": 21}'

  "{\"name\": \"Bob\", \"age\": 36}"
  |> json.decode(cjson.json_decode(converter))
  |> io.debug
  // Ok(Person("Bob", 36))
}
```

Further documentation can be found at <https://hexdocs.pm/convert_json>.

## Features

- Encode and decode to JSON.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
