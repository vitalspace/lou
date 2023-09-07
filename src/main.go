package main

/*
	#include <stdlib.h>
	#include <string.h>
*/
import "C"
import "fmt"

func ch(str string) *C.char {
	return C.CString(str)
}

func str(ch *C.char) string {
	return C.GoString(ch)
}

type FieldValidator func(interface{}) bool

func mian() {
	fmt.Println("Hello world")
}
