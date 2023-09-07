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

func stringValidator(value interface{}) bool {
	_, ok := value.(string)
	return ok
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
	user := `{ "name": "Juan", "email": "juan@email.com" }`

	userSchema := Schema{
		Fields: map[string]FieldValidator{
			"name":  stringValidator,
			"email": stringValidator,
		},
	}

	if !Validate(user, userSchema) {
		fmt.Println("Invalid data")
	} else {
		fmt.Println("Valid data")
	}
}
