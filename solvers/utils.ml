open Core
open Unix.Select_fds
open Sys
open Obj

let magical = Obj.magic;;

let float_of_bool = function
  | true -> 1.
  | false -> 0.

let join ?separator:(separator = " ") elements= String.concat ~sep:separator elements

(* let rec replicate (n : int) (x : 'a) : 'a list = *)
(*   if n <= 0 then [] else  x::(replicate (n - 1) x) *)

(* vector operations *)
let rec zeros n = if n <= 0 then [] else 0.0::(zeros (n - 1))

let (+|) a b = List.map2_exn ~f:(+.) a b

let ( *| ) a v = v |> List.map ~f:(fun x -> a*.x)

let compose f g = fun x -> f (g x);;
let (%) = compose;;

let fold1 f l = List.fold_right ~init:(List.hd_exn l) ~f:f (List.tl_exn l)

let is_some = function
  | None -> false
  | _ -> true;;
let get_some = function
  | Some(x) -> x
  | _ -> raise (Failure "get_some");;
let safe_get_some message = function
  | Some(x) -> x
  | _ -> raise (Failure message);;

let sum = List.fold_left ~f:(+) ~init:0

let minimum l = List.reduce_exn l ~f:min

let memorize f = 
  let table = Hashtbl.Poly.create () in
  fun x -> 
    match Hashtbl.Poly.find table x with
    | Some(y) -> y
    | None -> 
      let y = f x in
      ignore(Hashtbl.Poly.add table x y);
      y

let maximum_by ~cmp l = 
  List.fold_left ~init:(List.hd_exn l) (List.tl_exn l) ~f:(fun a b -> 
      if cmp a b > 0
      then a else b)

let rec map_list f = function
  | [] -> [f []]
  | (x :: xs) -> (f (x :: xs)) :: (map_list f xs)

let is_invalid (x : float) = x <> x || x = Float.infinity || x = Float.neg_infinity;;
let is_valid = compose not is_invalid;;

let rec last_one = function
  | [] -> raise (Failure "last_one: empty")
  | [x] -> x
  | _::y -> last_one y

let index_of l x = 
  let rec loop a r = 
    match r with
      [] -> raise (Failure "index_of: not found")
    | (y::ys) -> if y = x then a else loop (a+1) ys
  in loop 0 l

let set_equal c x y = 
  let x = List.sort ~cmp:c x
  and y = List.sort ~cmp:c y in
  List.compare c x y = 0


let log2 = log 2.

let lse x y = 
  if is_invalid x then y else if is_invalid y then x else
  if x > y
  then x +. log (1.0 +. exp (y-.x))
  else y +. log (1.0 +. exp (x-.y))

let softMax = lse


let lse_list (l : float list) : float = 
  List.fold_left l ~f:lse ~init:Float.neg_infinity

(* log difference exponential: log(e^x - e^y) = x+log(1-e^(y-x)) *)
let lde x y = 
  assert(x >= y);
  x +. log (1. -. exp (y-.x))


let rec remove_duplicates l = 
  match l with
  | [] -> []
  | (x::y) -> x::(List.filter ~f:(fun z -> not (z = x)) (remove_duplicates y))

let merge_a_list ls ~f:c =
  let merged = Hashtbl.Poly.create () in
  List.iter ls (fun l ->
      List.iter l (fun (tag,value) ->
          try
            let old_value = Hashtbl.find_exn merged tag in
            Hashtbl.set merged ~key:tag ~data:(c value old_value)
          with Not_found -> ignore(Hashtbl.add merged tag value)
        )
    );
  Hashtbl.to_alist merged


let combine_with f _ a b = 
  match (a,b) with
  | (None,_) -> b
  | (_,None) -> a
  | (Some(x),Some(y)) -> Some(f x y)

let flip f x y = f y x

let (--) i j = 
  let rec aux n acc =
    if n < i then acc else aux (n-1) (n :: acc)
  in aux j []

let range n = 0 -- (n-1);;


let float_interval (i : float) (s : float) (j : float) : float list = 
  let rec aux n acc =
    if n < i then acc else aux (n-.s) (n :: acc)
  in aux j []

(* let time () = *)
(*   let open Core.Time in *)
(*   Core.Time. *)
(*   Core.Time.to_float @@ Time.now () *)
let flush_everything () =
  flush stdout;
  flush stderr


let time_it description callback = 
  let start_time = Time.now () in
  let return_value = callback () in
  Printf.eprintf "%s in %s.\n" description (Time.diff (Time.now ()) start_time |> Time.Span.to_string); 
  flush_everything();
  return_value

let shuffle d = begin
    Random.self_init ();
    let nd = List.map ~f:(fun c -> (Random.bits (), c)) d in
    let sond = List.sort compare nd in
    List.map ~f:snd sond
  end

(* progress bar *)
type progress_bar = { maximum_progress : int; mutable current_progress : int; }

let make_progress_bar number_jobs = 
  { maximum_progress = number_jobs; current_progress = 0; }

let update_progress_bar bar new_progress = 
  let max = Float.of_int bar.maximum_progress in
  let old_dots = Int.of_float @@ Float.of_int bar.current_progress *. 80.0 /. max in
  let new_dots = Int.of_float @@ Float.of_int new_progress *. 80.0 /. max in
  bar.current_progress <- new_progress;
  if new_dots > old_dots then
    let difference = min 80 (new_dots-old_dots) in
    List.iter (1--difference) (fun _ -> print_char '.'; flush stdout)

  


let number_of_cores = ref 1;; (* number of CPUs *)
let counted_CPUs = ref false;; (* have we counted the number of CPUs? *)

let cpu_count () = 
  try match Sys.os_type with 
    | "Win32" -> int_of_string (safe_get_some "CPU_count" @@ Sys.getenv "NUMBER_OF_PROCESSORS") 
    | _ ->
      let i = Unix.open_process_in "getconf _NPROCESSORS_ONLN" in
      let close () = ignore (Unix.close_process_in i) in
      try Scanf.fscanf i "%d" (fun n -> close (); n) with e -> close (); raise e
      with
      | Not_found | Sys_error _ | Failure _ | Scanf.Scan_failure _ 
      | End_of_file | Unix.Unix_error (_, _, _) -> 1


let string_proper_prefix p s = 
  let rec loop n = 
    (n >= String.length p) ||
    (p.[n] = s.[n] && loop (n+1))
  in 
  String.length p < String.length s && loop 0

let rec remove_index i l = 
  match (i,l) with
  | (0,x::xs) -> (x,xs)
  | (i,x::xs) -> let (j,ys) = remove_index (i-1) xs in
    (j,x::ys)
  | _ -> raise (Failure "remove_index")

let rec random_subset l = function
  | 0 -> l
  | s -> 
    let i = Random.int (List.length l) in
    let (ith,r) = remove_index i l in
    ith :: (random_subset r (s-1))

let avg l = 
  List.fold_left ~init:0.0 ~f:(+.) l /. (Float.of_int @@ List.length l)

let pi = 4.0 *. atan 1.0

let normal s m =
  let u, v = Random.float 1.0, Random.float 1.0
  in let n = sqrt (-2.0 *. log u) *. cos (2.0 *. pi *. v)
  in
  s *. n +. m

let print_arguments () = 
  Array.iter Sys.argv ~f:(fun a -> Printf.printf "%s " a);
  print_newline ()

(* samplers adapted from gsl *)
let rec uniform_positive () = 
  let u = Random.float 1.0 in
  if u > 0.0 then u else uniform_positive ()

let uniform_interval ~l ~u =
  assert (u > l);
  let x = uniform_positive() in
  (l+.u)/.2. +. (u-.l)*.x


let rec sample_gamma a b = 
  if a < 1.0
  then
    let u = uniform_positive () in
    (sample_gamma (1.0 +. a) b) *. (u ** (1.0 /. a))
  else
    let d = a -. 1.0 /. 3.0 in
    let c = (1.0 /. 3.0) /. sqrt d in
    let rec loop () = 
      let rec inner_loop () = 
        let x = normal 1.0 0.0 in
        let v = 1.0 +. c *. x in
        if v > 0.0 then (v,x) else inner_loop ()
      in
      let (v,x) = inner_loop () in
      let v = v*.v*.v in
      let u = uniform_positive () in
      if (u < 1.0 -. 0.0331 *. x *. x *. x *. x) ||
         (log u < 0.5 *. x *. x +. d *. (1.0 -. v +. log v)) 
      then b *. d *. v
      else loop ()
    in loop ()


let sample_uniform_dirichlet a n = 
  let ts = List.map (1--n) ~f:(fun _ -> sample_gamma a 1.0) in
  let norm = List.fold_left ~init:0.0 ~f:(+.) ts  in
  List.map ts ~f:(fun t -> t/.norm)

(* let make_random_seeds n =  *)
(*   let rec seeds others m =  *)
(*     if m = 0 then others else *)
(*       let r = Random.bits () in *)
(*       if List.mem others r then seeds others m *)
(*           else seeds (r::others) (m-1) *)
(*   in seeds [] n *)


(*
let () = 
  let a =2. in
  let b = 2. in
  let samples = List.map (1--1000) ~f:(fun _ -> let (x,y) =(sample_gamma a 1.0,sample_gamma b 1.0) in
                                        x/.(x+.y)) in
  let mean = (List.fold_left ~init:0.0 ~f:(+.) samples /. 1000.0) in
  let variance =List.fold_left ~init:0.0 ~f:(+.) (List.map samples ~f:(fun s -> (s-.mean)*.(s-.mean)))
                /. 1000.0  in
  Printf.printf "mean: %f\n" mean;  
  Printf.printf "variance: %f\n" variance;;
*)


let command_output cmd =
  let ic, oc = Unix.open_process cmd in
  let buf = Buffer.create 16 in
  (try
     while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ());
  let _ = Unix.close_process (ic, oc) in
  (Buffer.contents buf)

let slice s e l =
  (*  we might want to make this always be safe *)
  List.slice l s e;;

let random_choice l =
  Random.int (List.length l) |> 
  List.nth_exn l

let compare_list c xs ys =
  let d = List.length xs - List.length ys in
  let rec r x y = match (x,y) with
    | ([],[]) -> 0
    | (a :: b, u :: v) ->
      let d = c a u in
      if d = 0 then r b v else d
    | _ -> assert false
  in 
  if d = 0 then r xs ys else d
