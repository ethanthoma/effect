import gleam/fetch
import gleam/http/request
import gleam/uri
import gleeunit

import gleeunit/should

import effect.{type Effect}

pub fn main() {
  gleeunit.main()
}

pub type Error {
  UriParse
  Fetch(fetch.FetchError)
  Any
}

pub fn google_test() {
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
  should.be_ok(res)
}
