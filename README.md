# effect

[![Package Version](https://img.shields.io/hexpm/v/effect)](https://hex.pm/packages/effect)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/effect/)

```sh
gleam add effect@1.2.0
```

This library includes an implementation of `Effect` that handles results differently.
See [effect_result](src/effect_result/README.md) for details.

```gleam
import effect

pub fn main() {
  let google: Effect(Result(String, Error)) = {
    use uri <- effect.try_replace_error(
      uri.parse("https://www.google.com"),
      UriParse,
    )
    use req <- effect.try_replace_error(request.from_uri(uri), UriParse)
    use res <- effect.try_await_map_error(fetch.send(req), Fetch)
    use text <- effect.try_await_map_error(fetch.read_text_body(res), Fetch)

    text.body |> Ok |> effect.dispatch
  }

  use res <- effect.perform(google)
  case res {
    Ok(body) -> io.println(body)
    Error(e) -> e |> string.inspect |> io.println_error
  }
}
```

Further documentation can be found at <https://hexdocs.pm/effect>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
