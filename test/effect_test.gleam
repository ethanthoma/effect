import gleam/fetch
import gleam/http/request
import gleam/int
import gleam/javascript/promise
import gleam/result
import gleam/string
import gleam/uri

import gleeunit
import gleeunit/should

import effect
import effect/promise as effect_promise

pub fn main() {
  gleeunit.main()
}

pub type Error {
  UriParse
  Fetch(fetch.FetchError)
  TextRead
}

pub fn normal_test() {
  let effect = {
    use a <- effect.from(1)
    use b <- effect.from(fn() { 5 }())
    effect.continue(a + b)
  }

  effect.pure(effect, should.equal(_, 6))
}

pub fn nested_test() {
  {
    use b <- effect.from_result(Error(""))
    use a <- effect.from_result(Ok(5))
    use c <- effect.from(2)
    a + b + c |> effect.continue
  }
  |> effect.perform(should.be_error)

  {
    use a <- effect.from_result(Ok(4))
    use b <- effect.from_result(Ok(2))
    use c <- effect.then(some_num(5))
    use d <- effect.map(some_num(6))
    a + b + c + d
  }
  |> effect.perform(should.be_ok)
}

fn some_num(num: Int) {
  use b <- effect.from_result(Ok(0))
  use a <- effect.from_result(Ok(num))
  use c <- effect.from(2)
  a + b + c |> effect.continue
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
      effect.replace_error(UriParse),
    )
    use req <- effect.from_result_replace_error(request.from_uri(uri), UriParse)
    use resp <- effect_promise.from_promise_result(fetch.send(req), Fetch)
    use text <- effect_promise.from_promise_result(
      fetch.read_text_body(resp),
      effect.replace_error(TextRead),
    )
    text.body |> effect.continue
  }
  |> effect.perform(should.be_ok)
}

pub fn math_test() -> effect.Effect(String, String) {
  use res <- effect.handle(divide(10, 0))

  case res {
    Ok(n) -> effect.continue("Result: " <> int.to_string(n))
    Error(e) -> effect.continue("Error: " <> e)
  }
}

fn divide(n: Int, d: Int) {
  case d {
    0 -> effect.throw("Division by zero")
    _ -> effect.continue(n / d)
  }
}

const registered_email = "test@exists.com"

pub fn user_test() {
  effect.pure(register_user(registered_email, "1234567890"), should.equal(
    _,
    ShowEmailInUse(registered_email),
  ))
  effect.pure(register_user("", "pass"), should.equal(_, ShowInvalidEmail("")))
  effect.pure(register_user("@", "pass"), should.equal(
    _,
    ShowInvalidPassword("pass"),
  ))
}

pub type ValidationError {
  InvalidEmail(String)
  InvalidPassword(String)
  DuplicateUser(String)
}

pub type RegisterResult {
  ShowInvalidEmail(String)
  ShowEmailInUse(String)
  ShowInvalidPassword(String)
  Success(User)
}

pub type User {
  User(email: String, pass: String)
}

fn validate_email(email: String) -> effect.Effect(String, ValidationError) {
  case string.contains(email, "@") {
    True -> effect.continue(email)
    False -> effect.throw(InvalidEmail(email))
  }
}

fn check_duplicate(email: String) -> effect.Effect(Bool, ValidationError) {
  case email {
    email if email == registered_email -> effect.throw(DuplicateUser(email))
    _ -> effect.continue(False)
  }
}

fn validate_password(pass: String) -> effect.Effect(String, ValidationError) {
  case string.length(pass) > 8 {
    True -> effect.continue(pass)
    False -> effect.throw(InvalidPassword(pass))
  }
}

fn register_user(
  email: String,
  password: String,
) -> effect.Effect(RegisterResult, any) {
  use email_result <- effect.handle({
    use email <- effect.then(validate_email(email))
    use _ <- effect.map(check_duplicate(email))
    email
  })
  use pass_result <- effect.handle(validate_password(password))

  let res = {
    use email <- result.try(email_result)
    use pass <- result.map(pass_result)
    #(email, pass)
  }

  case res {
    Ok(#(valid_email, valid_pass)) -> {
      effect.continue(Success(User(valid_email, valid_pass)))
    }
    Error(InvalidEmail(e)) -> effect.continue(ShowInvalidEmail(e))
    Error(DuplicateUser(e)) -> effect.continue(ShowEmailInUse(e))
    Error(InvalidPassword(e)) -> effect.continue(ShowInvalidPassword(e))
  }
}
