signature ARRAY_GLOBAL =
   sig
      eqtype 'a array
   end

signature ARRAY =
   sig
      include ARRAY_GLOBAL

      type 'a vector

      val all: ('a -> bool) -> 'a array -> bool
      val app: ('a -> unit) -> 'a array -> unit 
      val appi: (int * 'a -> unit) -> 'a array -> unit 
      val array: int * 'a -> 'a array 
      val collate: ('a * 'a -> order) -> 'a array * 'a array -> order
      val copy: {src: 'a array, dst: 'a array, di: int} -> unit 
      val copyVec: {src: 'a vector, dst: 'a array, di: int} -> unit 
      val exists: ('a -> bool) -> 'a array -> bool
      val find: ('a -> bool) -> 'a array -> 'a option
      val findi: (int * 'a -> bool) -> 'a array -> (int * 'a) option
      val foldl: ('a * 'b -> 'b) -> 'b -> 'a array -> 'b 
      val foldli: (int * 'a * 'b -> 'b) -> 'b -> 'a array -> 'b
      val foldr: ('a * 'b -> 'b) -> 'b -> 'a array -> 'b 
      val foldri: (int * 'a * 'b -> 'b) -> 'b -> 'a array -> 'b
      val fromList: 'a list -> 'a array 
      val length: 'a array -> int 
      val maxLen: int 
      val modify: ('a -> 'a) -> 'a array -> unit 
      val modifyi: (int * 'a -> 'a) -> 'a array -> unit 
      val sub: 'a array * int -> 'a 
      val tabulate: int * (int -> 'a) -> 'a array 
      val update: 'a array * int * 'a -> unit 
      val vector: 'a array -> 'a vector
   end

signature ARRAY_EXTRA =
   sig
      include ARRAY
      type 'a vector_slice
      structure ArraySlice: ARRAY_SLICE_EXTRA 
	where type 'a array = 'a array
	  and type 'a vector = 'a vector
	  and type 'a vector_slice = 'a vector_slice

      val rawArray: int -> 'a array
      val unsafeSub: 'a array * int -> 'a
      val unsafeUpdate: 'a array * int * 'a -> unit

      val concat: 'a array list -> 'a array
      val duplicate: 'a array -> 'a array
      val toList: 'a array -> 'a list
      val unfoldi: int * 'a * (int * 'a -> 'b * 'a) -> 'b array

      (* Deprecated *)
      val checkSlice: 'a array * int * int option -> int
      (* Deprecated *)
      val checkSliceMax: int * int option * int -> int
      (* Deprecated *)
      val extract: 'a array * int * int option -> 'a vector
   end
