import effect
import gleam/javascript/promise
import gleam/list

@target(javascript)
/// @proposal
/// this pattern is very common with promises
/// suggesting a helper that lets you unwrap the result and map the err
/// all in one go
/// edits: removed the map_function, made promise types explicit
pub fn from_promise(
  box: promise.Promise(Result(inner, error)),
  map_error: fn(error) -> early,
  handler: fn(inner) -> effect.Effect(msg, early),
) -> effect.Effect(msg, early) {
  effect.Effect(run: [
    fn(action: effect.Action(msg, early)) {
      {
        use inner <- promise.map(box)
        let effect.Effect(run:) = case inner {
          Ok(inner) -> handler(inner)
          Error(error) -> error |> map_error |> effect.throw
        }
        list.each(run, fn(run) { run(action) })
      }
      Nil
    },
  ])
}
