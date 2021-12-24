(** Copyright (c) 2020-2021 Sam Westrick
  *
  * See the file LICENSE for details.
  *)

structure PrettyUtil =
struct

  open TokenDoc
  infix 2 ++ $$ //
  infix 1 \\
  fun x ++ y = beside (x, y)
  fun x $$ y = aboveOrSpace (x, y)
  fun x // y = aboveOrBeside (x, y)
  fun x \\ y = group (x $$ indent y)

  fun seqWithSpaces elems f =
    if Seq.length elems = 0 then empty else
    Seq.iterate
      (fn (prev, tok) => prev ++ space ++ f tok)
      (f (Seq.nth elems 0))
      (Seq.drop elems 1)


  fun spaces n =
    List.foldl op++ empty (List.tabulate (n, fn _ => space))


  fun sequence openn delims close (xs: doc Seq.t) =
    if Seq.length xs = 0 then
      token openn ++ token close
    else
      let
        val top = token openn ++ softspace ++ Seq.nth xs 0
        fun f (delim, x) = token delim ++ space ++ x
      in
        group (
          Seq.iterate op// top (Seq.map f (Seq.zip (delims, Seq.drop xs 1)))
          //
          token close
        )
      end


  fun separateWithSpaces (items: doc option list) : doc =
    let
      val items: doc list = List.mapPartial (fn x => x) items
    in
      case items of
        [] => empty
      | first :: rest =>
          List.foldl (fn (next, prev) => prev ++ space ++ next) first rest
    end


  fun maybeShowSyntaxSeq s f =
    case s of
      Ast.SyntaxSeq.Empty => NONE
    | Ast.SyntaxSeq.One x => SOME (f x)
    | Ast.SyntaxSeq.Many {left, elems, delims, right} =>
        SOME (sequence left delims right (Seq.map f elems))

end
