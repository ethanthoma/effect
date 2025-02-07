import effect.{type Effect}
import effect/promise as effect_promise
import gleam/fetch.{type FetchBody, type FetchError}
import gleam/float
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/string
import gleam/uri

pub type Error {
  UriParse
  Fetch(fetch.FetchError)
  TextRead
}

pub fn readme_overview() {
  let google: Effect(String, Error) = {
    use uri <- effect.from_result_replace_error(
      uri.parse("https://www.google.com"),
      UriParse,
    )
    use req <- effect.from_result_replace_error(request.from_uri(uri), UriParse)
    use resp <- effect_promise.from_promise_result(fetch.send(req), Fetch)
    use text <- effect_promise.from_promise_result(
      fetch.read_text_body(resp),
      Fetch,
    )
    text.body |> effect.continue
  }

  use res: Result(String, Error) <- effect.perform(google)
  case res {
    Ok(body) -> body |> io.println
    Error(e) -> e |> string.inspect |> io.println_error
  }
}

pub fn readme_basic() {
  // Succeed / Fail shortcuts
  // Effect(Int, early)
  let eff_ok = effect.continue(42)
  // Effect(msg, String)
  let eff_err = effect.throw("Oops!")

  // Combine
  let eff: Effect(Int, String) = {
    case int.random(2) |> int.is_even {
      True -> eff_ok
      False -> eff_err
    }
  }

  // Perform
  use res: Result(Int, String) <- effect.perform(eff)

  case res {
    Ok(num) -> io.println("Got: " <> int.to_string(num))
    Error(err) -> io.println("Error: " <> err)
  }
}

type TooSmallError {
  TooSmallError
}

pub fn readme_chain() {
  let computation: Effect(Int, TooSmallError) = {
    let effect: Effect(Int, TooSmallError) = effect.continue(10)
    use num: Int <- effect.then(effect)
    case num < 5 {
      True -> effect.throw(TooSmallError)
      False -> effect.continue(num * 2)
    }
  }

  let computation: Effect(Float, TooSmallError) = {
    use num: Int <- effect.map(computation)
    let f: Float = int.to_float(num)
    // fun fact, I added this func to std
    let log: Float = float.exponential(f)
  }

  use res: Result(Float, TooSmallError) <- effect.perform(computation)
  case res {
    Ok(n) -> io.println("Final result: " <> float.to_string(n))
    Error(TooSmallError) -> io.println("Error: num is too small!")
  }
}

fn fetch_data_readme() -> promise.Promise(
  Result(response.Response(fetch.FetchBody), fetch.FetchError),
) {
  let assert Ok(uri) = uri.parse("https://www.google.com")
  let assert Ok(req) = request.from_uri(uri)
  fetch.send(req)
}

pub fn promises_readme() {
  let eff: Effect(String, Error) = {
    // fetch from google
    let prom = fetch_data_readme()
    use fetch_body: Response(FetchBody) <- effect_promise.from_promise_result(
      prom,
      Fetch,
    )

    // read the response from FetchBody to String
    let prom: Promise(Result(Response(String), FetchError)) =
      fetch.read_text_body(fetch_body)

    use text: Response(String) <- effect_promise.from_promise_result(
      prom,
      // map the error
      Fetch,
      // replace: effect.replace_error(TextRead), keep: effect.keep_error 
    )

    // return just the body
    text.body |> effect.continue
  }

  use res: Result(String, Error) <- effect.perform(eff)
  case res {
    // Server Data
    Ok(body) -> io.println(body)
    // Network Error
    Error(Fetch(msg)) -> io.println("Failed: " <> string.inspect(msg))
    _ -> io.println("Failed: other error")
  }
}

pub fn pure_readme() {
  let eff: Effect(Int, effect.Nothing) = {
    use a <- effect.from(5)
    use b <- effect.from(2)
    a * b |> effect.continue
  }

  use num: Int <- effect.pure(eff)
  num |> int.to_string |> io.println
}
