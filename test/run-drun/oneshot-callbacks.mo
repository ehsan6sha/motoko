import Prim "mo:⛔";

actor a {

  public shared func oneshot_ping() : () {
    Prim.debugPrint("ping! " # debug_show Prim.rts_callback_table_count());
  };

  public func go() : async () {
    Prim.debugPrint("go 0: " # debug_show Prim.rts_callback_table_count());
    oneshot_ping();
    await async {Prim.debugPrint("go 1: " # debug_show Prim.rts_callback_table_count())};
    oneshot_ping();
    ignore await (async {assert false; 42});
  };
};
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"

//SKIP run
//SKIP run-low
//SKIP run-ir
