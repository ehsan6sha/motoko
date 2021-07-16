import Prim "mo:⛔";

actor a {

  public shared func oneshot_ping() : () {
    Prim.debugPrint("ping! " # debug_show Prim.rts_callback_table_count());
  };

  public func go() : async () {
    Prim.debugPrint("go 0: " # debug_show Prim.rts_callback_table_count());
    let a1 = oneshot_ping();
    Prim.debugPrint("go 1: " # debug_show Prim.rts_callback_table_count());
    oneshot_ping();
    ignore await (async 42);
    Prim.debugPrint("go 2: " # debug_show Prim.rts_callback_table_count());
    assert false;
  };
};
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"
await a.go(); //OR-CALL ingress go "DIDL\x00\x00"

//SKIP run
//SKIP run-low
//SKIP run-ir
