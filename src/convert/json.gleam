import convert as c
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// Encode a value into the corresponding Json using the converter.  
/// If the converter isn't valid, a NullValue is returned.
pub fn json_encode(value: a, converter: c.Converter(a)) -> json.Json {
  value |> c.encode(converter) |> encode_value
}

/// Decode a Json string using the provided converter.
pub fn json_decode(
  converter: c.Converter(a),
) -> fn(String) -> Result(a, json.DecodeError) {
  let decoder = decoder(c.type_def(converter))

  fn(value: String) {
    use glitr_value <- result.try(
      value
      |> json.parse(decoder),
    )

    glitr_value |> c.decode(converter) |> result.map_error(json.UnableToDecode)
  }
}

/// Decode a Json bit array using the provided converter.
pub fn json_decode_bits(
  converter: c.Converter(a),
) -> fn(BitArray) -> Result(a, json.DecodeError) {
  let decoder = decoder(c.type_def(converter))

  fn(value: BitArray) {
    use glitr_value <- result.try(
      value
      |> json.parse_bits(decoder),
    )

    glitr_value |> c.decode(converter) |> result.map_error(json.UnableToDecode)
  }
}

/// Encode a GlitrValue into its corresponding JSON representation.  
/// This is not meant to be used directly !  
/// It is better to use converters.
pub fn encode_value(val: c.GlitrValue) -> json.Json {
  case val {
    c.StringValue(v) -> json.string(v)
    c.BoolValue(v) -> json.bool(v)
    c.FloatValue(v) -> json.float(v)
    c.IntValue(v) -> json.int(v)
    c.BitArrayValue(v) -> json.string(bit_array.base64_url_encode(v, True))
    c.ListValue(vals) -> json.array(vals, encode_value)
    c.DictValue(v) ->
      json.array(v |> dict.to_list, fn(keyval) {
        json.array([keyval.0, keyval.1], encode_value)
      })
    c.ObjectValue(v) ->
      json.object(list.map(v, fn(f) { #(f.0, encode_value(f.1)) }))
    c.OptionalValue(v) -> json.nullable(v, encode_value)
    c.ResultValue(v) ->
      case v {
        Ok(res) ->
          json.object([
            #("type", json.string("ok")),
            #("value", encode_value(res)),
          ])
        Error(err) ->
          json.object([
            #("type", json.string("error")),
            #("value", encode_value(err)),
          ])
      }
    c.EnumValue(variant, v) ->
      json.object([
        #("variant", json.string(variant)),
        #("value", encode_value(v)),
      ])
    _ -> json.null()
  }
}

/// Create a Gleam decoder for the provided GlitrType.
/// This is not meant to be used directly !
/// It is better to use converters.
pub fn decoder(of: c.GlitrType) -> decode.Decoder(c.GlitrValue) {
  case of {
    c.String -> decode.string |> decode.map(c.StringValue)
    c.Bool -> decode.bool |> decode.map(c.BoolValue)
    c.Float -> decode.float |> decode.map(c.FloatValue)
    c.Int -> decode.int |> decode.map(c.IntValue)
    c.BitArray ->
      decode.string
      |> decode.then(fn(base64_str) {
        let base64_data =
          base64_str
          |> bit_array.base64_url_decode

        case base64_data {
          Ok(bits) -> decode.success(c.BitArrayValue(bits))
          Error(_) ->
            decode.failure(c.NullValue, "Expected a base64 encoded BitArray")
        }
      })
    c.Dynamic -> decode.dynamic |> decode.map(c.DynamicValue)
    c.List(el) -> decode.list(decoder(el)) |> decode.map(c.ListValue)
    c.Dict(k, v) ->
      decode.dict(decoder(k), decoder(v)) |> decode.map(c.DictValue)
    c.Optional(of) ->
      decode.optional(decoder(of)) |> decode.map(c.OptionalValue)
    c.Object(fields) -> object_decoder(decode.success([]), fields)
    c.Result(res, err) ->
      decode.at(["type"], decode.string)
      |> decode.then(fn(type_val) {
        case type_val {
          "ok" ->
            decode.at(["value"], decoder(res))
            |> decode.map(Ok)
            |> decode.map(c.ResultValue)
          "error" ->
            decode.at(["value"], decoder(err))
            |> decode.map(Error)
            |> decode.map(c.ResultValue)
          _other -> decode.failure(c.NullValue, "Type must be 'ok' or 'error'")
        }
      })
    c.Enum(variants:) ->
      decode.at(["variant"], decode.string)
      |> decode.then(fn(variant_name) {
        case list.key_find(variants, variant_name) {
          Ok(variant_def) ->
            decode.at(["value"], decoder(variant_def))
            |> decode.map(fn(value) { c.EnumValue(variant_name, value) })
          Error(_) ->
            decode.failure(
              c.NullValue,
              "Variant must be one of: "
                <> variants |> list.map(fn(v) { v.0 }) |> string.join("/"),
            )
        }
      })
    c.Null -> decode.success(c.NullValue)
  }
}

fn object_decoder(
  fields_decoder: decode.Decoder(List(#(String, c.GlitrValue))),
  fields: List(#(String, c.GlitrType)),
) -> decode.Decoder(c.GlitrValue) {
  case fields {
    [] ->
      fields_decoder
      |> decode.map(fn(fields) {
        fields
        |> list.reverse
        |> c.ObjectValue
      })
    [#(name, of), ..rest] ->
      fields_decoder
      |> decode.then(fn(fields) {
        use field_val <- decode.field(name, decoder(of))
        decode.success([#(name, field_val), ..fields])
      })
      |> object_decoder(rest)
  }
}
