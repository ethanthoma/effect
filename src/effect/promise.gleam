import gleam/javascript/promise

import effect

@target(javascript)
/// Creates an effect from a promise that contains a result.
///
/// Maps the error of the result, operates on the inner
/// value of the result through the handler.
/// ```gleam
/// let promise: Promise(Result(ok, err))
/// use ok: ok <- from_promise_result(promise, fn (previous_error) { new_error }) // map the error here
/// effect.succeed(ok) // Effect(ok, err)
/// ```
pub fn from_promise_result(
  box: promise.Promise(Result(inner, error)),
  map_error: fn(error) -> early,
  handler: fn(inner) -> effect.Effect(msg, early),
) -> effect.Effect(msg, early) {
  let eff =
    box
    |> effect.unbox(promise.map)
    |> effect.then(effect.wrap_result)

  use res <- effect.handle(eff)
  case res {
    Ok(inner) -> inner |> handler
    Error(error) -> error |> map_error |> effect.throw
  }
}

@target(javascript)
/// Creates an effect from a promise, operates on the inner value
/// through the handler.
/// ```gleam
/// let promise: Promise(inner)
/// use inner: inner <- from_promise(promise)
/// effect.succeed(inner) // Effect(inner, early)
/// ```
pub fn from_promise(
  box: promise.Promise(inner),
  handler: fn(inner) -> effect.Effect(msg, early),
) -> effect.Effect(msg, early) {
  box
  |> effect.unbox(promise.map)
  |> effect.then(handler)
}
