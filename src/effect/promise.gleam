import gleam/javascript/promise

import effect

@target(javascript)
/// @proposal
/// this pattern is very common with promises
/// suggesting a helper that lets you unwrap the result and map the err
/// all in one go
/// edits: removed the map_function, made promise types explicit
///
pub fn from_promise(
  box: promise.Promise(Result(inner, error)),
  map_error: fn(error) -> early,
  handler: fn(inner) -> effect.Effect(msg, early),
) -> effect.Effect(msg, early) {
  let eff = effect.then(effect.unbox(box, promise.map), effect.wrap_result)

  use res <- effect.handle(eff)
  case res {
    Ok(inner) -> inner |> handler
    Error(error) -> error |> map_error |> effect.throw
  }
}
