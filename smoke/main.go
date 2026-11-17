// Command smoke links gocv against a built archive the same way gbgrader/MarkIt does and checks that
// OpenCV works: it draws, encodes and decodes an image.
package main

import (
	"fmt"
	"image"
	"image/color"
	"os"

	"gocv.io/x/gocv"
)

func main() {
	want := os.Args[1]
	if got := gocv.OpenCVVersion(); got != want {
		fail("OpenCV version is %s, want %s", got, want)
	}

	img := gocv.NewMatWithSize(64, 64, gocv.MatTypeCV8UC1)
	defer img.Close()
	gocv.Circle(&img, image.Pt(32, 32), 10, color.RGBA{R: 255, G: 255, B: 255}, -1)

	buf, err := gocv.IMEncode(gocv.PNGFileExt, img)
	if err != nil {
		fail("encoding png: %v", err)
	}
	defer buf.Close()

	decoded, err := gocv.IMDecode(buf.GetBytes(), gocv.IMReadGrayScale)
	if err != nil {
		fail("decoding png: %v", err)
	}
	defer decoded.Close()

	if n := gocv.CountNonZero(decoded); n < 300 || n > 340 {
		fail("decoded circle has %d white pixels, want about 314", n)
	}
	fmt.Println("smoke test passed with OpenCV", gocv.OpenCVVersion())
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
