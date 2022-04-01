package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"

	nixpath "github.com/nix-community/go-nix/pkg/nixpath"
	"github.com/urfave/cli/v2"
	_ "modernc.org/sqlite"
)

func main() {
	app := &cli.App{}
	app.UseShortOptionHandling = true
	app.Flags = []cli.Flag{
		&cli.StringFlag{
			Name:    "db-path",
			Aliases: []string{"d"},
			Value:   "cache.db",
			EnvVars: []string{"DB_PATH"},
		},
	}
	app.Commands = []*cli.Command{
		{
			Name:  "grep",
			Usage: "grep JSON lines",
			Flags: []cli.Flag{
				&cli.BoolFlag{
					Name:    "invert",
					Aliases: []string{"v"},
					Value:   false,
				},
			},
			Action: func(c *cli.Context) error {
				return Run(callFuncGrep, c.String("db-path"), c.Bool("invert"))
			},
		},
		{
			Name:  "activate",
			Usage: "update active boolean in JSON lines",
			Flags: []cli.Flag{},
			Action: func(c *cli.Context) error {
				return Run(callFuncActivation, c.String("db-path"), false)
			},
		},
	}
	if err := app.Run(os.Args); err != nil {
		log.Fatal(err)
	}
}

type Path string
type Element struct {
	Active      bool   `json:"active"`
	AttrPath    string `json:"attrPath"`
	OriginalUri string `json:"originalUri"`
	StorePaths  []Path `json:"storePaths"`
	Uri         string `json:"uri"`
	Error       string `json:"error,omitempty"`
}

func callFuncGrep(err error, element *Element, built int) error {
	if err == nil && built == 0 {
		element.Active = false
		err = fmt.Errorf("disabling")
	}
	return err
}

func callFuncActivation(err error, element *Element, built int) error {
	if (err == nil && built == 0) || err != nil {
		element.Active = false
	}
	return nil
}

func Run(handler func(error, *Element, int) error, conn string, invert bool) error {
	db, err := sql.Open("sqlite", conn)
	if err != nil {
		log.Fatal(err)
	}
	stmt, err := db.Prepare("SELECT built FROM cache WHERE id = ?")
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	scanner := bufio.NewScanner(os.Stdin)
loop:
	for scanner.Scan() {
		var e Element
		// Otherwise an empty array is null when marshaled to JSON
		e.StorePaths = make([]Path, 0)
		e.Active = true

		err = json.Unmarshal(scanner.Bytes(), &e)
		if err != nil {
			log.Fatal(err)
		}
		flag := false
		for _, p := range e.StorePaths {
			var built int
			m := nixpath.PathRe.FindStringSubmatch(string(p))
			if m == nil {
				log.Fatalf("unable to parse path %v", p)
			}
			err := stmt.QueryRow(m[1]).Scan(&built)
			err = handler(err, &e, built)
			if err != nil {
				flag = true
			}
		}
		if flag != invert {
			continue loop
		}
		res, err := json.Marshal(e)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(string(res))
	}

	if err = scanner.Err(); err != nil {
		log.Fatal(err)
		// Handle error.
	}

	if err = db.Close(); err != nil {
		return err
	}
	return nil
}
