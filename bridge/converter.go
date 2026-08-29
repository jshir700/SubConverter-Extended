package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"runtime/debug"
	"unsafe"

	"github.com/metacubex/mihomo/common/convert"
)

// ReleaseUnusedMemory forces the embedded Go runtime to return unused heap
// pages after an unusually large subscription parse.
//
//export ReleaseUnusedMemory
func ReleaseUnusedMemory() {
	debug.FreeOSMemory()
}

// ResolveAgeRecipient validates one Age public or secret key and returns a
// canonical public recipient plus a SHA-256 fingerprint. Errors intentionally
// do not include the supplied key.
//
//export ResolveAgeRecipient
func ResolveAgeRecipient(key *C.char) *C.char {
	if key == nil {
		result, _ := json.Marshal(ageRecipientResult{Error: "invalid age key"})
		return C.CString(string(result))
	}

	resolved, err := resolveAgeRecipient(C.GoString(key))
	if err != nil {
		resolved = ageRecipientResult{Error: err.Error()}
	}
	result, _ := json.Marshal(resolved)
	return C.CString(string(result))
}

// EncryptAgeArmored encrypts a successful configuration response using the
// resolved public recipient. The OK/ERROR prefix keeps the C boundary simple;
// valid armored output can never be confused with an error.
//
//export EncryptAgeArmored
func EncryptAgeArmored(data *C.char, recipient *C.char) *C.char {
	if data == nil || recipient == nil {
		return C.CString("ERROR\ninvalid age encryption input")
	}

	encrypted, err := encryptAgeArmored(C.GoString(data), C.GoString(recipient))
	if err != nil {
		return C.CString("ERROR\n" + err.Error())
	}
	return C.CString("OK\n" + encrypted)
}

// ConvertSubscription parses native Mihomo provider YAML or URI subscriptions.
//
//export ConvertSubscription
func ConvertSubscription(data *C.char) (result *C.char) {
	// Recover from panics in mihomo library to prevent crashing the entire process
	defer func() {
		if r := recover(); r != nil {
			errJSON, _ := json.Marshal(map[string]string{
				"error": "mihomo parser panic: " + fmt.Sprint(r),
			})
			result = C.CString(string(errJSON))
		}
	}()

	if data == nil {
		return C.CString(`{"error": "null input"}`)
	}

	// Convert C string to Go string
	subscription := C.GoString(data)

	// Expand binary Mieru links before preprocessing. A standard protobuf
	// Base64 payload may contain '+', which QueryUnescape correctly treats as
	// a space for URLs but must not touch inside mieru:// payloads.
	subscription = expandMieruStandardSubscription(subscription)

	// Preprocess subscription to fix URL encoding issues (e.g., v2rayN exported links)
	subscription = preprocessSubscription(subscription)

	// Call mihomo's converter
	proxies, err := convert.ConvertsV2Ray([]byte(subscription))
	if err != nil {
		errJSON, _ := json.Marshal(map[string]string{
			"error": err.Error(),
		})
		return C.CString(string(errJSON))
	}

	// Marshal result to JSON
	marshaled, err := json.Marshal(proxies)
	if err != nil {
		errJSON, _ := json.Marshal(map[string]string{
			"error": "failed to marshal result: " + err.Error(),
		})
		return C.CString(string(errJSON))
	}

	return C.CString(string(marshaled))
}

// FreeString frees memory allocated by Go (must be called from C++ after using the result)
//
//export FreeString
func FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {
	// Required for buildmode=c-archive
}
