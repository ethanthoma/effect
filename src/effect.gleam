import gleam/javascript/promise
import gleam/list

/// The `Effect` type represents a description of side effects as data. Each
/// effect specifies:
/// 1. The operations to perform
/// 2. The type of messages that will be sent back to your program
///
pub opaque type Effect(msg) {
  Effect(run: List(fn(Actions(msg)) -> Nil))
}

type Actions(msg) {
  Actions(dispatch: fn(msg) -> Nil)
}

/// Helper function similar to clip's parameter function. Provides an alternative
/// syntax for building curried functions. The following are equivalent:
///
/// ```gleam
/// fn(a) { fn(b) { thing(a, b) } }
///
/// {
///   use a <- param
///   use b <- param
///   thing(a, b)
/// }
/// ```
///
/// Mostly used internally.
///
pub fn param(f: fn(a) -> b) -> fn(a) -> b {
  f
}

/// Create an effect that does nothing. This is useful when you need to return
/// an effect but don't actually want to perform any operations.
///
pub fn none() -> Effect(msg) {
  Effect(run: [])
}

/// Create a custom effect from a function that takes a dispatch callback.
/// The dispatch callback can be used to send messages back to your program.
///
/// ```gleam
/// from(fn(dispatch) {
///   dispatch(MyMessage)
/// })
/// ```
pub fn from(effect: fn(fn(msg) -> Nil) -> Nil) -> Effect(msg) {
  Effect(run: [fn(actions: Actions(msg)) { effect(actions.dispatch) }])
}

/// Transform the messages produced by an effect. This is useful when you need
/// to adapt effects from one part of your program to work with another.
///
/// ```gleam
/// effect
/// |> map(fn(msg) { TransformedMessage(msg) })
/// ```
pub fn map(effect: Effect(a), f: fn(a) -> b) -> Effect(b) {
  let run = {
    use eff <- list.map(effect.run)

    {
      use actions: Actions(b) <- param

      let dispatch = {
        use msg <- param

        let Actions(dispatch:) = actions
        msg |> f |> dispatch
      }

      Actions(dispatch:) |> eff
    }
  }

  Effect(run:)
}

/// Transform an effect containing a Result by providing a function that operates on
/// the success value and returns another Result-containing effect. This is useful
/// for chaining effects where each step can potentially fail. Errors from either
/// the input effect or the transformation function will short-circuit the chain.
///
/// ```gleam
/// use response <- map_result(initial_effect)
/// handle_response(response)
/// ```
pub fn map_result(
  effect: Effect(Result(a, e)),
  f: fn(a) -> Effect(Result(b, e)),
) -> Effect(Result(b, e)) {
  Effect(run: [
    fn(actions) {
      effect
      |> perform(fn(result) {
        case result {
          Ok(value) -> {
            let Effect(run) = f(value)
            list.each(run, fn(run) { actions |> run })
          }
          Error(e) -> actions.dispatch(Error(e))
        }
      })
    },
  ])
}

/// Handle a Result by providing a function that produces an effect for the
/// success case. Errors are automatically converted into effects.
///
/// ```gleam
/// use data <- try(parse_data())
/// process_data(data)
/// ```
pub fn try(
  res: Result(value, error),
  f: fn(value) -> Effect(Result(b, error)),
) -> Effect(Result(b, error)) {
  case res {
    Ok(value) -> f(value)
    Error(e) ->
      from({
        use dispatch <- param
        e |> Error |> dispatch
      })
  }
}

/// Similar to `try` but allows mapping error values before they're dispatched.
/// You can emulate this using `try` and `result.map_error`.
///
/// ```gleam
/// use response <- try_map_error(
///   fetch.send(request),
///   fn(e) { NetworkError(e) }
/// )
/// process_response(response)
/// ```
pub fn try_map_error(
  res: Result(value, error),
  map_error: fn(error) -> new_error,
  f: fn(value) -> Effect(Result(b, new_error)),
) -> Effect(Result(b, new_error)) {
  case res {
    Ok(value) -> f(value)
    Error(e) ->
      from({
        use dispatch <- param
        e |> map_error |> Error |> dispatch
      })
  }
}

/// Similar to `try` but allows replacing error values before they're dispatched.
/// You can emulate this using `try` and `result.replace_error`.
///
/// ```gleam
/// use response <- try_replace_error(
///   fetch.send(request),
///   NetworkError,
/// )
/// process_response(response)
/// ```
pub fn try_replace_error(
  res: Result(value, error),
  e: new_error,
  f: fn(value) -> Effect(Result(b, new_error)),
) -> Effect(Result(b, new_error)) {
  case res {
    Ok(value) -> f(value)
    Error(_) ->
      from({
        use dispatch <- param
        e |> Error |> dispatch
      })
  }
}

@target(javascript)
/// Handle a Promise containing a Result by providing a function that produces
/// an effect for the success case. This is particularly useful for handling
/// async operations like HTTP requests.
///
/// ```gleam
/// use response <- try_await(fetch.send(request))
/// process_response(response)
/// ```
pub fn try_await(
  pres: promise.Promise(Result(value, error)),
  f: fn(value) -> Effect(Result(b, error)),
) -> Effect(Result(b, error)) {
  Effect(run: [
    fn(actions) {
      promise.map(pres, fn(result) {
        case result {
          Ok(value) -> {
            let Effect(run:) = f(value)
            list.each(run, {
              use run <- param
              actions |> run
            })
          }
          Error(e) -> e |> Error |> actions.dispatch
        }
      })
      Nil
    },
  ])
}

@target(javascript)
/// Similar to `try_await` but allows mapping error values before they're
/// dispatched. This is commonly used when you want to wrap external errors
/// in your own error type.
///
/// ```gleam
/// use response <- try_await_map_error(
///   fetch.send(request),
///   fn(e) { NetworkError(e) }
/// )
/// process_response(response)
/// ```
pub fn try_await_map_error(
  pres: promise.Promise(Result(value, error)),
  map_error: fn(error) -> new_error,
  f: fn(value) -> Effect(Result(b, new_error)),
) -> Effect(Result(b, new_error)) {
  Effect(run: [
    fn(actions) {
      promise.map(pres, fn(result) {
        case result {
          Ok(value) -> {
            let Effect(run:) = f(value)
            list.each(run, {
              use run <- param
              actions |> run
            })
          }
          Error(e) -> e |> map_error |> Error |> actions.dispatch
        }
        Nil
      })
      Nil
    },
  ])
}

@target(javascript)
/// Similar to `try_await` but allows replacing error values before they're
/// dispatched. This is commonly used when you want to wrap external errors
/// in your own error type.
///
/// ```gleam
/// use response <- try_await_replace_error(
///   fetch.send(request),
///   NetworkError,
/// )
/// process_response(response)
/// ```
pub fn try_await_replace_error(
  pres: promise.Promise(Result(value, error)),
  e: new_error,
  f: fn(value) -> Effect(Result(b, new_error)),
) -> Effect(Result(b, new_error)) {
  Effect(run: [
    fn(actions) {
      promise.map(pres, fn(result) {
        case result {
          Ok(value) -> {
            let Effect(run:) = f(value)
            list.each(run, {
              use run <- param
              actions |> run
            })
          }
          Error(_) -> e |> Error |> actions.dispatch
        }
        Nil
      })
      Nil
    },
  ])
}

/// Run an effect by providing a dispatch function that will receive any
/// messages produced by the effect.
///
/// ```gleam
/// effect
/// |> perform(fn(msg) {
///   case msg {
///     Ok(data) -> handle_success(data)
///     Error(e) -> handle_error(e)
///   }
/// })
/// ```
pub fn perform(effect: Effect(msg), dispatch: fn(msg) -> any) -> Nil {
  let dispatch = {
    use msg <- param
    dispatch(msg)
    Nil
  }

  let actions = Actions(dispatch:)
  list.each(effect.run, {
    use run <- param
    actions |> run
  })
}

/// Convert a value into an effect that will dispatch that value when performed.
///
/// ```gleam
/// value
/// |> dispatch
/// |> perform(handle_value)
/// ```
pub fn dispatch(value: a) -> Effect(a) {
  from({
    use dispatch <- param
    value |> dispatch
  })
}
