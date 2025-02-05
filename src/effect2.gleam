import gleam/list
import gleam/option

/// The `Effect` type represents computations that might return early or continue with a value.
/// Each effect specifies:
///
/// 1. The type of the continue value (`msg`)
/// 2. The type of early return value (`early`)
///
pub opaque type Effect(msg, early) {
  Effect(run: List(fn(Action(msg, early)) -> Nil))
}

/// An `Action` represents how to handle both successful and early return paths of an effect.
type Action(msg, early) {
  Action(next: Next(msg), not: Not(early))
}

/// A function that handles the successful path of an effect.
pub type Next(msg) =
  fn(msg) -> Nil

/// A function that handles the early return path of an effect.
pub type Not(early) =
  fn(early) -> Nil

/// Creates an effect that succeeds with the given value.
///
/// ```gleam
/// let effect = dispatch(42)
/// ```
pub fn dispatch(value: msg) -> Effect(msg, early) {
  Effect(run: [fn(act: Action(msg, early)) { act.next(value) }])
}

/// Chains together two effects where the second effect depends on the result of the first.
///
/// ```gleam
/// let effect = {
///   use a <- flat_map(get_user())
///   use b <- flat_map(get_posts(a.id))
///   dispatch(b)
/// }
/// ```
pub fn flat_map(
  effect: Effect(msg_1, early),
  f: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  Effect(run: [
    fn(act) {
      let act =
        Action(..act, next: fn(msg_1) {
          let Effect(run: runs) = f(msg_1)
          list.each(runs, fn(run) { run(act) })
        })

      list.each(effect.run, fn(run) { run(act) })
    },
  ])
}

/// Executes an effect, handling both success and failure paths with a callback.
///
/// ```gleam
/// perform(effect, fn(res) {
///   case res {
///     Ok(value) -> io.println("Success: " <> value)
///     Error(err) -> io.println("Error: " <> err)
///   }
/// })
/// ```
pub fn perform(
  effect: Effect(msg, early),
  handler: fn(Result(msg, early)) -> any,
) -> Nil {
  let act =
    Action(
      next: fn(msg) {
        handler(Ok(msg))
        Nil
      },
      not: fn(early) {
        handler(Error(early))
        Nil
      },
    )

  list.each(effect.run, fn(run) { run(act) })
}

/// Transforms the successful values of an effect using the given function.
///
/// ```gleam
/// let effect = dispatch(5)
///   |> map(fn(n) { n * 2 })
/// ```
pub fn map(
  effect: Effect(msg, early),
  handler: fn(msg) -> msg_2,
) -> Effect(msg_2, early) {
  Effect(run: {
    use run <- list.map(effect.run)

    fn(act: Action(msg_2, early)) -> Nil {
      let next = fn(msg: msg) -> Nil {
        let Action(next:, not: _) = act
        msg |> handler |> next
      }

      Action(..act, next:) |> run
    }
  })
}

/// Transforms the early return values of an effect using the given function.
///
/// ```gleam
/// let effect = throw("error")
///   |> map_early(fn(e) { CustomError(e) })
/// ```
pub fn map_early(
  effect: Effect(msg, early),
  handler: fn(early) -> early_2,
) -> Effect(msg, early_2) {
  Effect(run: {
    use run <- list.map(effect.run)

    fn(act: Action(msg, early_2)) -> Nil {
      let not = fn(early: early) -> Nil {
        let Action(next: _, not:) = act
        early |> handler |> not
      }
      Action(..act, not:) |> run
    }
  })
}

/// Creates an effect from a value and a function that produces an effect.
///
/// ```gleam
/// let effect = from(5, fn(n) { dispatch(n * 2) })
/// ```
pub fn from(
  value: msg_1,
  f: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  flat_map(dispatch(value), f)
}

/// Creates an effect that returns early with the given value.
///
/// ```gleam
/// let effect = throw("Something went wrong")
/// ```
pub fn throw(value: early) -> Effect(msg, early) {
  Effect(run: [fn(act: Action(msg, early)) { act.not(value) }])
}

/// Creates an effect from a Result, where Ok values are passed to the given function
/// and Error values cause an early return.
///
/// ```gleam
/// let effect = from_result(parse_int("123"), fn(n) { dispatch(n * 2) })
/// ```
pub fn from_result(
  value: Result(msg_1, early),
  f: fn(msg_1) -> Effect(msg_2, early),
) -> Effect(msg_2, early) {
  case value {
    Ok(msg_1) -> f(msg_1)
    Error(early) -> throw(early)
  }
}

/// Creates an effect from an Option, where Some values are passed to the given function
/// and None causes an early return.
pub fn from_option(
  value: option.Option(msg_1),
  f: fn(msg_1) -> Effect(msg_2, option.Option(msg_2)),
) -> Effect(msg_2, option.Option(msg_2)) {
  case value {
    option.Some(msg_1) -> f(msg_1)
    option.None -> throw(option.None)
  }
}

/// Creates an effect from a boxed value (like a Promise), using the provided unboxing function
/// and a function to create an effect from the unboxed value.
///
/// ```gleam
/// let effect = from_box(promise, promise.map, fn(value) { dispatch(value) })
/// ```
pub fn from_box(
  box: box,
  unbox_fn: fn(box, fn(inner) -> Nil) -> any,
  f: fn(inner) -> Effect(msg, early),
) -> Effect(msg, early) {
  Effect(run: [
    fn(action: Action(msg, early)) {
      {
        use inner <- unbox_fn(box)
        let Effect(run:) = f(inner)
        list.each(run, fn(run) { run(action) })
      }
      Nil
    },
  ])
}

/// Handles both success and failure paths of an effect, allowing transformation into a new effect
/// with potentially different types.
///
/// ```gleam
/// let effect = {
///   use res <- handle(validate_input(data))
///   case res {
///     Ok(valid) -> dispatch(ShowSuccess(valid))
///     Error(err) -> dispatch(ShowError(err))
///   }
/// }
/// ```
pub fn handle(
  effect: Effect(msg_1, early_1),
  handler: fn(Result(msg_1, early_1)) -> Effect(msg_2, early_2),
) -> Effect(msg_2, early_2) {
  Effect(run: [
    fn(act) {
      let act =
        Action(
          next: fn(msg_1) {
            let Effect(run: runs) = handler(Ok(msg_1))
            list.each(runs, fn(run) { run(act) })
          },
          not: fn(msg_2) {
            let Effect(run: runs) = handler(Error(msg_2))
            list.each(runs, fn(run) { run(act) })
          },
        )
      list.each(effect.run, fn(run) { run(act) })
    },
  ])
}

/// Type representing the absence of an early return value.
pub type Nothing

/// Executes an effect that is known to be pure (cannot have early returns).
/// The handler only needs to handle the success case.
///
/// ```gleam
/// let pure_effect = dispatch(42)
/// pure(pure_effect, fn(n) { io.println(int.to_string(n)) })
/// ```
pub fn pure(effect: Effect(msg, Nothing), handler: fn(msg) -> any) -> Nil {
  let act =
    Action(
      next: fn(msg) {
        handler(msg)
        Nil
      },
      not: fn(_) { panic as "how?" },
    )

  list.each(effect.run, fn(run) { run(act) })
}
