#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <caml/callback.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/threads.h>
#include <caml/printexc.h>

/* --------------------
 * Initialize
 * -------------------- */

// OCaml is not reentrant; we need to acquire a lock before we call OCaml
// functions from C. Each thread also needs to be registered.

// https://caml.inria.fr/pub/docs/manual-ocaml/intfc.html#s%3AC-multithreading

void lock() {
  caml_acquire_runtime_system();
}

void unlock() {
  caml_release_runtime_system();
}

bool check_exception(const char* ctx1, const char* ctx2, const char* ctx3, value v) {
  if (Is_exception_result(v)) {
    printf (
      "WARNING: Exception thrown (%s -> %s -> %s) %s\n",
      ctx1, ctx2, ctx3,
      caml_format_exception (Extract_exception (v)));
    fflush(stdout);
    unlock();
    return false;
  }
  return true;
}

bool check_null_closure(const char* ctx1, const char* ctx2, const char* ctx3, value *v) {
  if (v == NULL) {
    printf (
      "WARNING: Closure not found (%s -> %s -> %s)\n",
      ctx1, ctx2, ctx3);
    fflush(stdout);
    unlock();
    return false;
  }
  return true;
}

bool check_string(const char* ctx1, const char* ctx2, const char* ctx3, value v) {
  check_exception(ctx1, ctx2, ctx3, v);
  if (Tag_val(v) != String_tag) {
    printf("WARNING: Value is expected to be a string but isn't! (%s -> %s -> %s)\n",
      ctx1, ctx2, ctx3);
    fflush(stdout);
    unlock();
    return false;
  }
  return true;
}

// Allocates memory of exactly the size of the bytes in the value, and copies the
// data into it. Returns the new memory.
char* copy_bytes_outside_runtime(value v) {
  if (!check_string("", "copy_bytes_outside_runtime", "", v)) {
    return NULL;
  }
  int length = caml_string_length(v);
  void* dest = malloc(length);
  memcpy(dest, String_val(v), length);
  return dest;
}

// Allocates memory sized 1 byte larger than the string in the value, copies
// the data, and adds a NULL byte at the end. Returns the new memory.
char* copy_string_outside_runtime(const char* ctx1, const char* ctx2, value v) {
  if (!check_string(ctx1, ctx2, "copy_string_outside_runtime", v))
    return NULL;

  // OCaml strings can have NULL bytes in them, so don't use strndup
  int length = caml_string_length(v);
  char* dest = malloc(length+1);
  memcpy(dest, String_val(v), length);
  dest[length] = '\0';
  return dest;
}

extern char* dark_init_ocaml() {
  char* argv[2];
  argv[0] = "";
  argv[1] = NULL;
  printf("OCAML loaded!\n");
  value res = caml_startup_exn(argv);
  check_exception("dark_init_ocaml", "caml_startup_exn", "", res);
  printf("Registering main thread!\n");
  caml_c_thread_register();
  // The main thread holds the lock - we need to release it or other threads
  // calling lock() will hang.
  caml_release_runtime_system();
  return strdup("loaded");
}

void register_thread() {
  caml_c_thread_register();
}

/* --------------------
 * Convert from json to binary strings
 * //FSTODO check for memory leaks in these functions
 * -------------------- */
char* call_bin2json(const char* callback_name, void* bytes, int length) {
  lock();
  value v = caml_alloc_initialized_string(length, bytes);
  if (!check_string(callback_name, "call_bin2json", "caml_alloc_initialized_string", v))
    return NULL;
  value* closure = caml_named_value(callback_name);
  if (!check_null_closure(callback_name, "call_bin2json", "", closure))
    return NULL;
  if (!check_exception(callback_name, "closure", "caml_named_value", *closure))
    return NULL;
  value result = caml_callback_exn(*closure, v);
  if (!check_exception(callback_name, "result", "caml_callback_exn", result))
    return NULL;
  char* retval = copy_string_outside_runtime(callback_name, "call_bin2json", result);
  unlock();
  return retval;
}
extern char* user_fn_bin2json(void* bytes, int length) {
  return call_bin2json("user_fn_bin2json", bytes, length);
}
extern char* user_tipe_bin2json(void* bytes, int length) {
  return call_bin2json("user_tipe_bin2json", bytes, length);
}
extern char* handler_bin2json(void* bytes, int length) {
  return call_bin2json("handler_bin2json", bytes, length);
}
extern char* db_bin2json(void* bytes, int length) {
  return call_bin2json("db_bin2json", bytes, length);
}
extern char* oplist_bin2json(void* bytes, int length) {
  return call_bin2json("oplist_bin2json", bytes, length);
}
extern char* pos_bin2json(void* bytes, int length) {
  return call_bin2json("pos_bin2json", bytes, length);
}
extern char* expr_bin2json(void* bytes, int length) {
  return call_bin2json("expr_bin2json", bytes, length);
}
extern char* expr_tlid_pair_bin2json(void* bytes, int length) {
  return call_bin2json("expr_tlid_pair_bin2json", bytes, length);
}

/* --------------------
 * Convert from json to binary strings
 * //FSTODO check for memory leaks in these functions
 * -------------------- */

// out_bytes is an out parameter, it passes a pointer to a memory location. We allocate memory then write the location into which we insert
int call_json2bin(const char* callback_name, char* json, void** out_bytes) {
  lock();
  value* closure = caml_named_value(callback_name);
  if (!check_null_closure(callback_name, "call_json2bin", "", closure))
    return 0;
  if (!check_exception(callback_name, "call_json2bin", "caml_named_value", *closure))
    return 0;
  value v = caml_copy_string(json); // has a strlen, think it's safe here
  if (!check_string(callback_name, "call_json2bin", "caml_copy_string", v))
    return 0;

  value result = caml_callback_exn(*closure, v);
  int length = caml_string_length(result);
  *out_bytes = copy_bytes_outside_runtime(result);
  unlock();
  return length;
}
extern int user_fn_json2bin(char* json, void** out_bytes) {
  return call_json2bin("user_fn_json2bin", json, out_bytes);
}
extern int user_tipe_json2bin(char* json, void** out_bytes) {
  return call_json2bin("user_tipe_json2bin", json, out_bytes);
}
extern int handler_json2bin(char* json, void** out_bytes) {
  return call_json2bin("handler_json2bin", json, out_bytes);
}
extern int db_json2bin(char* json, void** out_bytes) {
  return call_json2bin("db_json2bin", json, out_bytes);
}
extern int oplist_json2bin(char* json, void** out_bytes) {
  return call_json2bin("oplist_json2bin", json, out_bytes);
}
extern int pos_json2bin(char* json, void** out_bytes) {
  return call_json2bin("pos_json2bin", json, out_bytes);
}
extern int expr_json2bin(char* json, void** out_bytes) {
  return call_json2bin("expr_json2bin", json, out_bytes);
}
extern int expr_tlid_pair_json2bin(char* json, void** out_bytes) {
  return call_json2bin("expr_tlid_pair_json2bin", json, out_bytes);
}

/* --------------------
 * Dvals
 * Strings can contain NULL bytes so we always use byte arrays and pass a length.
 * -------------------- */
const int string_to_string (const char* callback_name, char* bytesIn, int lengthIn, char** bytesOut) {
  lock();
  value* closure = caml_named_value(callback_name);
  if (!check_null_closure(callback_name, "string_to_string", "", closure))
    return 0;

  if (!check_exception(callback_name, "string_to_string", "caml_named_value", *closure))
    return 0;
  value v = caml_alloc_initialized_string(lengthIn, bytesIn);
  if (!check_string(callback_name, "string_to_string", "copy_string", v))
    return 0;

  value result = caml_callback_exn(*closure, v);
  if (!check_string(callback_name, "string_to_string", "callback_exn", result))
    return 0;

  char* retval = copy_string_outside_runtime(callback_name, "string_to_string", result);
  *bytesOut = retval;
  int lengthOut = caml_string_length(result);
  unlock();
  return lengthOut;
}

extern int to_internal_roundtrippable_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_internal_roundtrippable_v0", bytesIn, lengthIn, bytesOut);
}

extern int of_internal_roundtrippable_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("of_internal_roundtrippable_v0", bytesIn, lengthIn, bytesOut);
}

extern int to_internal_queryable_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_internal_queryable_v0", bytesIn, lengthIn, bytesOut);
}

extern int to_internal_queryable_v1 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_internal_queryable_v1", bytesIn, lengthIn, bytesOut);
}

extern int of_internal_queryable_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("of_internal_queryable_v0", bytesIn, lengthIn, bytesOut);
}

extern int of_internal_queryable_v1 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("of_internal_queryable_v1", bytesIn, lengthIn, bytesOut);
}

extern int to_developer_repr_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_developer_repr_v0", bytesIn, lengthIn, bytesOut);
}

extern int to_enduser_readable_text_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_enduser_readable_text_v0", bytesIn, lengthIn, bytesOut);
}

extern int to_pretty_machine_json_v1 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_pretty_machine_json_v1", bytesIn, lengthIn, bytesOut);
}

extern int to_url_string (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_url_string", bytesIn, lengthIn, bytesOut);
}

extern int to_hashable_repr (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("to_hashable_repr", bytesIn, lengthIn, bytesOut);
}

extern int of_unknown_json_v1 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("of_unknown_json_v1", bytesIn, lengthIn, bytesOut);
}

extern int hash_v0 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("hash_v0", bytesIn, lengthIn, bytesOut);
}

extern int hash_v1 (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("hash_v1", bytesIn, lengthIn, bytesOut);
}

extern int execute (char* bytesIn, int lengthIn, char** bytesOut) {
  return string_to_string("execute", bytesIn, lengthIn, bytesOut);
}

/* --------------------
 * OCaml values
 * -------------------- */
extern char* digest () {
  lock();
  value* digest_value = caml_named_value("digest");
  if (!check_null_closure("digest", "", "", digest_value))
    return NULL;
  char* result = copy_string_outside_runtime("digest", "caml_named_value", *digest_value);
  unlock();
  return result;
}