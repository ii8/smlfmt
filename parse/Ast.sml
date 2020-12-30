(** Copyright (c) 2020 Sam Westrick
  *
  * See the file LICENSE for details.
  *)


(** See AstType.sml for the type definition. *)
structure Ast =
struct

  open AstType

  structure MaybeLong =
  struct
    open AstType.MaybeLong
  end

  structure SyntaxSeq =
  struct
    open AstType.SyntaxSeq
  end

  structure Ty =
  struct
    open AstType.Ty
  end

  structure Pat =
  struct
    open AstType.Pat
  end

  structure Exp =
  struct
    open AstType.Exp

    fun isAtExp exp =
      case exp of
        Const _ => true
      | Ident _ => true
      | Record _ => true
      | Select _ => true
      | Unit _ => true
      | Tuple _ => true
      | List _ => true
      | Sequence _ => true
      | LetInEnd _ => true
      | Parens _ => true
      | _ => false

    fun isAppExp exp =
      isAtExp exp orelse
      (case exp of
        App _ => true
      | _ => false)

    fun isInfExp exp =
      isAppExp exp orelse
      (case exp of
        Infix _ => true
      | _ => false)
  end

end
