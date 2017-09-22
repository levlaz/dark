open Core
open Types

(* ------------------------- *)
(* Values *)
(* ------------------------- *)
module DvalMap = String.Map
type dval_map = dval DvalMap.t [@opaque]
and dval = DInt of int
         | DStr of string
         | DChar of char
         | DFloat of float
         | DBool of bool
         | DAnon of id * (dval list -> dval)
         | DList of dval list
         (* TODO: make null more like option. Maybe that's for the type
            system *)
         | DNull
         | DObj of dval_map
         | DIncomplete [@@deriving show, sexp]

let rec to_repr_ (indent: int) (dv : dval) : string =
  let nl = "\n" ^ (String.make indent ' ') in
  let inl = "\n" ^ (String.make (indent + 2) ' ') in
  let indent = indent + 2 in
  match dv with
  | DInt i -> string_of_int i
  | DBool true -> "true"
  | DBool false -> "false"
  | DStr s -> "\"" ^ s ^ "\""
  | DFloat f -> string_of_float f
  | DChar c -> "'" ^ (Char.to_string c) ^ "'"
  | DAnon (id, _) -> "<anon:" ^ string_of_int id ^ ">"
  | DIncomplete -> "<incomplete>"
  | DNull -> "null"
  | DList l ->
      if List.is_empty l
      then "[]"
      else
        "[ " ^ inl ^
        (String.concat ~sep:", " (List.map ~f:(to_repr_ indent) (List.take l 10)))
        ^ nl ^ "]"
  | DObj o ->
    if DvalMap.is_empty o
    then "{}"
    else
        let strs = DvalMap.fold o
          ~init:[]
          ~f:(fun ~key ~data l -> (key ^ ": " ^ (to_repr_ indent data)) :: l) in
        "{ " ^ inl ^
        (String.concat ~sep:("," ^ inl) (List.take strs 10))
        ^ nl ^ "}"

let to_repr (dv : dval) : string =
  to_repr_ 0 dv



let to_comparable_repr (dvm : dval_map) : string =
  Map.to_alist ~key_order:`Increasing dvm
  |> List.map ~f:(fun (s, dv) -> s ^ (to_repr dv))
  |> List.fold ~f:(fun a b -> a ^ b) ~init:""

let dummy_compare dv1 dv2 =
  String.compare (to_repr dv1) (to_repr dv2)

module RealDvalMap = Map.Make (struct
    type t = dval

    let compare = dummy_compare
    let t_of_sexp = dval_of_sexp
    let sexp_of_t = sexp_of_dval
  end)

let rec to_string (dv : dval) : string =
  match dv with
  | DInt i -> string_of_int i
  | DBool true -> "true"
  | DBool false -> "false"
  | DStr s -> s
  | DFloat f -> string_of_float f
  | DChar c -> Char.to_string c
  | DAnon _ -> "<anon>"
  | DIncomplete -> "<incomplete>"
  | DNull -> "null"
  | DList l ->
    "[ " ^ ( String.concat ~sep:", " (List.map ~f:to_string l)) ^ " ]"
  | DObj o ->
    let strs = DvalMap.fold o
        ~init:[]
        ~f:(fun ~key ~data l -> (key ^ ": " ^ to_string data) :: l) in

    "{ " ^ (String.concat ~sep:", " strs) ^ " }"

let rec equal_dval (a: dval) (b: dval) =
  match (a,b) with
  | DInt i1, DInt i2 -> i1 = i2
  | DBool b1, DBool b2 -> b1 = b2
  | DStr s1, DStr s2 -> s1 = s2
  | DFloat f1, DFloat f2 -> f1 = f2
  | DChar c1, DChar c2 -> c1 = c2
  | DNull, DNull -> true
  | DIncomplete, DIncomplete -> true
  | DList l1, DList l2 -> List.equal ~equal:equal_dval l1 l2
  | DObj o1, DObj o2 -> DvalMap.equal equal_dval o1 o2
  | _, _ -> false

let get_type (dv : dval) : string =
  match dv with
  | DInt _ -> "Integer"
  | DStr _ -> "String"
  | DBool _ -> "Bool"
  | DFloat _ -> "Float"
  | DChar _ -> "Char"
  | DNull -> "Nothing"
  | DAnon _ -> "Anonymous function"
  | DList _ -> "List"
  | DObj _ -> "Object"
  | DIncomplete -> "n/a"
  (* | _ -> failwith "get_type not implemented yet" *)

let to_error_repr (dv : dval) : string =
  (to_repr dv) ^ " (" ^ (get_type dv) ^ ")"

let to_char (dv : dval) : char =
  match dv with
  | DChar c -> c
  | _ -> Exception.raise "Not a char"

(* ------------------------- *)
(* JSON *)
(* ------------------------- *)

let rec dval_of_yojson_ (json : Yojson.Safe.json) : dval =
  match json with
  | `Int i -> DInt i
  | `String s -> DStr s
  | `Bool b -> DBool b
  | `Float f -> DFloat f
  | `Null -> DNull
  | `Assoc alist -> DObj (List.fold_left
                        alist
                        ~f:(fun m (k,v) -> DvalMap.add m k (dval_of_yojson_ v))
                        ~init:DvalMap.empty)
  | `List l -> DList (List.map ~f:dval_of_yojson_ l)
  | j -> DStr ( "<todo, incomplete conversion: "
                ^ (Yojson.Safe.to_string j)
                ^ ">")

let rec dval_of_yojson (json : Yojson.Safe.json) : (dval, string) result =
  Result.Ok (dval_of_yojson_ json)

let rec dval_to_yojson (v : dval) : Yojson.Safe.json =
  match v with
  | DInt i -> `Int i
  | DBool b -> `Bool b
  | DStr s -> `String s
  | DFloat f -> `Float f
  | DNull -> `Null
  | DChar c -> `String (Char.to_string c)
  | DAnon _ -> `String "<anon>"
  | DIncomplete -> `String "<incomplete>"
  | DList l -> `List (List.map (List.take l 10) dval_to_yojson)
  | DObj o -> o
              |> DvalMap.to_alist
              |> List.map ~f:(fun (k,v) -> (k, dval_to_yojson v))
              |> (fun a -> `Assoc a)

let dval_to_json_string (v: dval) : string =
  v |> dval_to_yojson |> Yojson.Safe.to_string

(* ------------------------- *)
(* Parsing *)
(* ------------------------- *)
let parse (str : string) : dval =
  (* TODO: Doesn't handle characters. Replace with a custom parser,
     using the one in RealWorldOcaml, or just ripped out of Yojson *)
  if String.length str > 0 && String.get str 0 = '\''
  then DChar (String.get str 1)
  else str |> Yojson.Safe.from_string |> dval_of_yojson_


(* ------------------------- *)
(* Functions *)
(* ------------------------- *)
type execute_t = (dval_map -> dval)

type argument = AEdge of int
              | AConst of dval [@@deriving yojson, show]

let blank_arg = AConst DIncomplete

module ArgMap = String.Map
type arg_map = argument ArgMap.t

type param = { name: string
             ; tipe: string
             ; arity : int
             ; optional : bool
             ; description : string
             } [@@deriving yojson, show]
(* types  *)
type tipe = string
let tInt = "Integer"
let tStr = "String"
let tChar = "Char"
let tBool = "Bool"
let tObj = "Object"
let tList = "List"
(* placeholder until typesystem becomes more complete *)
let tAny = "Any"
let tFun = "Function"

type ccfunc = InProcess of (dval list -> dval)
            | API of (dval_map -> dval)

type fn = { name : string
          ; other_names : string list
          ; parameters : param list
          ; return_type : tipe
          ; description : string
          ; preview : (dval list -> dval list) option
          ; func : ccfunc
          ; pure : bool
          }

let param_to_string (param: param) : string =
  param.name
  ^ (if param.optional then "?" else "")
  ^ " : "
  ^ param.tipe


exception TypeError of dval list

let exe (fn: fn) (args: dval_map) : dval =
  try
    match fn.func with
    | InProcess f -> fn.parameters
                     |> List.map ~f:(fun (p: param) -> p.name)
                     |> List.map ~f:(DvalMap.find_exn args)
                     |> f
    | API f -> f args
  with
  | TypeError args ->
    Exception.raise
      ("Incorrect type to fn "
       ^ fn.name
       ^ ": expected ["
       ^ String.concat ~sep:", " (List.map ~f:param_to_string fn.parameters)
       ^ "], got ["
       ^ String.concat ~sep:", " (List.map ~f:to_error_repr args)
       ^ "]")

let exe_dv (fn : dval) (_: dval list) : dval =
  match fn with
  | dv -> dv
          |> to_error_repr
          |> (^) "Calling non-function: "
          |> Exception.raise
