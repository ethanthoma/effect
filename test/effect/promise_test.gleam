import gleam/fetch
import gleam/http/request
import gleam/javascript/promise
import gleam/result
import gleam/uri

import gleeunit/should

import effect
import effect/promise as effect_promise

pub type Error {
  UriParse
  Fetch(fetch.FetchError)
  TextRead
}

pub fn promise_test() {
  {
    use uri <- effect.from_result(
      uri.parse("https://www.google.com") |> result.replace_error(UriParse),
    )
    use req <- effect.from_result(
      request.from_uri(uri) |> result.replace_error(UriParse),
    )
    use resp <- effect.from_box(fetch.send(req), promise.map)
    use resp <- effect.from_result(resp |> result.map_error(Fetch))
    use text <- effect.from_box(fetch.read_text_body(resp), promise.map)
    use text <- effect.from_result(text |> result.map_error(Fetch))
    text.body |> effect.continue
  }
  |> effect.perform(should.be_ok)
}

pub fn promise_test_from_promise() {
  {
    use uri <- effect.from_result_map_error(
      uri.parse("https://www.google.com"),
      fn(_) { UriParse },
    )
    use req <- effect.from_result_replace_error(request.from_uri(uri), UriParse)
    use resp <- effect_promise.from_promise_result(fetch.send(req), Fetch)
    use text <- effect_promise.from_promise_result(
      fetch.read_text_body(resp),
      fn(_) { TextRead },
    )
    text.body |> effect.continue
  }
  |> effect.perform(should.be_ok)
}
