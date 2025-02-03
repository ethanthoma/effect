A lightweight library for modeling asynchronous effects and error handling in Gleam, inspired by [effect-ts](https://github.com/Effect-TS/core). 

This library allows you to treat asynchronous operations and potential failures as **first-class effectful computations**, which can be composed in a purely functional style before finally being executed.

The motivation was to create an API for dealing with promises from [gleam_promises](https://hexdocs.pm/gleam_javascript/gleam/javascript/promise.html) without having to "color" functions.

## Table of Contents

1. [Overview](#overview)  
2. [Usage](#usage)  
   - [Basic Construction](#basic-construction)  
   - [Chaining Effects](#chaining-effects)  
   - [Handling Promises](#handling-promises)  
   - [Performing the Effect](#performing-the-effect)  

## Overview

- **Asynchronous & Error-Encoded**: Each `Effect(a, e)` can produce either an `Ok(a)` (success) or an `Error(e)` (failure).  
- **Composable**: Build up complex workflows using `map`, `map_error`, and `try`.  
- **Lifts Promises**: Bridge JavaScript `promise.Promise(Result(a, e))` into the Gleam effect world with `from_promise`, `try_await`, and `try_await_map_error`.  
- **Perform**: Nothing executes until you call `perform(effect, callback)`. This separates definition from execution.

## Usage

Below are common usage scenarios demonstrating how to create and compose effects, handle failures, work with promises, and finally execute the effect.

### Basic Construction

```gleam
import effect/effect_result as effect
import gleam/io

pub fn main() {
  // Construct an effect from a plain Result:
  let eff_from_result = effect.from_result(Ok("Hello"))

  // Succeed / Fail shortcuts:
  let eff_ok = effect.succeed(42)
  let eff_err = effect.fail("Oops!")

  // Perform them:
  effect.perform(eff_from_result, fn(res) {
    case res {
      Ok(str) -> io.println("Got: " <> str)
      Error(err) -> io.println("Error: " <> err)
    }
  })
}
```

### Chaining Effects

Use `try` to sequence operations, only continuing on success, or short-circuiting on error:

```gleam
import effect/effect_result as effect
import gleam/io

type TooSmallError {
  TooSmallError
}

pub fn main() {
  let computation =
    effect.succeed(10)
    // successful effect
    |> effect.try(fn(x: Int) {
      // 
      case x < 5 {
        True -> effect.fail(TooSmallError)
        False -> effect.succeed(x * 2)
      }
    })
    |> effect.map(fn(double: Int) { double + 1 })

  effect.perform(computation, fn(res: Result(Int, TooSmallError)) {
    case res {
      // prints 21 if x=10
      Ok(n) -> io.println("Final result: " <> int.to_string(n))
      // TooSmallError
      Error(_err) -> io.println("Error: " <> "Too small!")
    }
  })
}
```

### Handling Promises

You can convert a `promise.Promise(Result(a, e))` into an `Effect(a, e)` using `from_promise`. Then compose it with `try_await` to sequence a follow-up effect:

```gleam
type FetchError {
  FetchError(String)
}


fn fetch_data() -> promise.Promise(Result(String, FetchError)) {
  // For example, some JavaScript network call
  promise.new(fn(resolve) {
    // resolve(Ok("Server data"))
    resolve(Error(FetchError("Network error")))
  })
}

fn main() {
  // `try_await` waits for Ok(a), then calls `f(a) -> Effect(b, e)`
  let eff =
    effect.try_await(fetch_data(), fn(data) {
      // do something with the data
      effect.from_result(Ok("Got data: " <> data))
    })

  effect.perform(eff, fn(res) {
    case res {
      // Server Data
      Ok(msg) -> io.println(msg)
      // Network Error
      Error(FetchError(msg)) -> io.println("Failed: " <> msg)
    }
  })
}
```

If you need to map the error type *before* continuing, use `try_await_map_error`.

### Performing the Effect

**Remember**: constructing an effect is purely declarative. It doesn’t do anything until you call `perform(effect, callback)`. This function:

1. Builds an internal `Actions(a, e)` record with `dispatch = callback`.
2. Iterates over the list of effect steps, passing each one the `Actions`.
3. Each step calls `dispatch` with `Ok(...)` or `Error(...)`.
