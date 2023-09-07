package main

/*
	#include <stdlib.h>
	#include <string.h>
*/
import "C"
import (
	"encoding/json"
	"fmt"
)

func ch(str string) *C.char {
	return C.CString(str)
}

func str(ch *C.char) string {
	return C.GoString(ch)
}

type FieldValidator func(interface{}) bool

type Schema struct {
	Fields map[string]FieldValidator
}

func Validate(jsonString string, schema Schema) bool {
	isValid := true

	var data map[string]interface{}

	err := json.Unmarshal([]byte(jsonString), &data)
	if err != nil {
		return false
	}

	for key, validator := range schema.Fields {
		if value, ok := data[key]; ok {
			if !validator(value) {
				isValid = false
			}
		} else {
			isValid = false // required field is missing
		}
	}
	return isValid
}

func mian() {
	fmt.Println("Hello world")
}
