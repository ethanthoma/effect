<h1 align="center">Effect</h1>

<div align="center">
  <strong>effectual computations made easy</strong>
</div>

<div align="center">
  <a href="https://hex.pm/packages/lustre">
    <img src="https://img.shields.io/hexpm/v/effect" alt="Package Version"/>
  </a>
  <a href="https://hexdocs.pm/effect/">
    <img src="https://img.shields.io/badge/hex-docs-ffaff3" alt="Docs"/>
  </a>
</div>

![](image.webp)

## Table of Contents

1. [Overview](#overview)  
1. [Example](#example)  
1. [Installation](#installation)  
1. [Usage](#usage)
    - [Basic Construction](#basic-construction)  
    - [Chaining Effects](#chaining-effects)  
    - [Handling Promises](#handling-promises)

## Overview

A small library for handling side effects! Particularly promises in Gleam.

Inspired by [Lustre](https://github.com/lustre-labs/lustre)'s Effects and [effect-ts](https://github.com/Effect-TS/core).

This library allows you to treat async operations and potential failures as 
**first-class effectful computations**, which can be composed before finally being executed.

The motivation was to create an API for dealing with promises from [gleam_promises](https://hexdocs.pm/gleam_javascript/gleam/javascript/promise.html).

## Example

```gleam
import effect

pub type Error {
  UriParse
  Fetch(fetch.FetchError)
}

pub fn main() {
  let google: Effect(String, Error) = {
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

  use res: Result(String, Error) <- effect.perform(google)
  case res {
    Ok(body) -> body |> io.println
    Error(e) -> e |> string.inspect |> io.println_error
  }
}
```

Further documentation can be found at <https://hexdocs.pm/effect>.

## Installation

```sh
gleam add effect@2.0.0
```

## Usage

Below are demonstrations of common usages demonstrating on how to create and compose effects, 
handle failures, work with promises, and actually `perform` the effect.

### Basic Construction

```gleam
import gleam/int
import gleam/io

import effect.{type Effect}

pub fn main() {
  // Succeed / Fail shortcuts
  let eff_ok: Effect(Int, early) = effect.continue(42)
  let eff_err: Effect(msg, String) = effect.throw("Oops!")

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
```

### Chaining Effects

Use `then` and `map` to sequence operations, only continuing on success, or short-circuiting on error:

```gleam
import gleam/float
import gleam/int
import gleam/io

import effect.{type Effect}

type TooSmallError {
  TooSmallError
}

pub fn main() {
  let computation: Effect(Int, TooSmallError) = {
    let effect: Effect(Int, early) = effect.continue(10)
    use num: Int <- effect.then(effect)
    case num < 5 {
        True -> effect.throw(TooSmallError)
        False -> effect.continue(num * 2)
    }
  }

  let computation: Effect(Float, TooSmallError) = {
    use num: Int <- effect.map(computation)
    let f: Float = int.to_float(num)
    let log: Float = float.exponential(f) // fun fact, I added this func to std
  }

  use res: Result(Float, TooSmallError) <- effect.perform(computation)
  case res {
    Ok(n) -> io.println("Final result: " <> float.to_string(n))
    Error(TooSmallError) -> io.println("Error: num is too small!")
  }
}
```

### Handling Promises

You can convert a `promise.Promise(Result(a, e))` into an `Effect(a, e)` using 
`from_box` and `promise.map`.

```gleam
import gleam/fetch.{type FetchBody, type FetchError}
import gleam/javascript/promise.{type Promise}
import gleam/string

import effect.{type Effect}

type Error {
  Fetch(fetch.FetchError)
}

fn fetch_data() -> Promise(Result(FetchBody, FetchError)) {
  let assert Ok(uri) = uri.parse("https://www.google.com")
  let assert Ok(req) = request.from_uri(uri)
  fetch.send(req)
}

fn main() {
  let eff: Effect(String, Error) = {
    // fetch from google
    let prom = fetch_data()
    use res: Result(FetchBody, FetchError) <- effect.from_box(prom, promise.map)
    use fetch_body: FetchBody <- effect.from_result(res |> result.map_error(Fetch))

    // read the response from FetchBody to String
    let prom: Promise(Result(String, FetchError)) = fetch.read_text_body(fetch_body)
    use text: Result(String, FetchError) <- effect.from_box(prom, promise.map)
    use text: String <- effect.from_result(text |> result.map_error(Fetch))

    // return just the body
    text.body |> effect.continue
  }

  use res: Result(String, Error) <- effect.perform(eff)
  case res {
    // Server Data
    Ok(body) -> io.println(body)
    // Network Error
    Error(Fetch(msg)) -> io.println("Failed: " <> string.inspect(msg))
  }
}
```

For more, be sure to checkout the [test cases](./test/effect_test.gleam).
