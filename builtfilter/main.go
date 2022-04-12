package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path"
	"sync"
	"time"

	"github.com/marianogappa/parseq"
	nixpath "github.com/nix-community/go-nix/pkg/nixpath"
	log "github.com/sirupsen/logrus"
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
		&cli.BoolFlag{
			Name:    "update",
			Aliases: []string{"u"},
			Value:   false,
		},
		&cli.BoolFlag{
			Name:  "debug",
			Value: false,
		},
		&cli.StringFlag{
			Name:  "substituter",
			Value: "https://cache.nixos.org/",
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
				return Run(c, false)
			},
		},
		{
			Name:  "activate",
			Usage: "update active boolean in JSON lines",
			Flags: []cli.Flag{},
			Action: func(c *cli.Context) error {
				return Run(c, true)
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

func Run(c *cli.Context, activate bool) error {
	if c.Bool("debug") {
		log.SetLevel(log.DebugLevel)
	}
	conn := c.String("db-path")
	update := c.Bool("update")
	invert := c.Bool("invert")
	db, err := sql.Open("sqlite", conn)
	if err != nil {
		log.Fatal(err)
	}
	_, err = db.Exec("CREATE TABLE if NOT EXISTS cache (id TEXT PRIMARY KEY, built INTEGER, last_mod INTEGER, last_accessed INTEGER);")
	if err != nil {
		log.Fatal(err)
	}
	var mu sync.Mutex

	stmt, err := db.Prepare("SELECT built FROM cache WHERE id = ?")
	if err != nil {
		log.Fatal(err)
	}
	updateStmt, err := db.Prepare(`
	INSERT into cache (id,built,last_mod,last_accessed) VALUES
	(?,?,?,?)
	ON CONFLICT(id)
	DO UPDATE SET
	built = excluded.built,
	last_accessed = excluded.last_accessed,
	last_mod = CASE built != excluded.built
		WHEN true then excluded.last_mod
		WHEN false then last_mod
		END
	`)
	if err != nil {
		log.Fatal(err)
	}
	defer stmt.Close()

	scanLines := func(p parseq.ParSeq) {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			in := make([]byte, len(scanner.Bytes()))
			copy(in, scanner.Bytes())
			p.Input <- in
		}
		if err = scanner.Err(); err != nil {
			log.Fatal(err)
			// Handle error.
		}
		close(p.Input)
	}
	process := func(value interface{}) interface{} {
		substituter, err := url.Parse(c.String("substituter"))
		substituterOrigPath := substituter.Path
		if err != nil {
			log.Fatal(err)
		}
		v := value.([]byte)
		var e Element
		// Otherwise an empty array is null when marshaled to JSON
		e.StorePaths = make([]Path, 0)
		e.Active = true

		err = json.Unmarshal(v, &e)
		if err != nil {
			log.Printf("input was %s yay \n", string(v))
			panic(err)
		}
		for _, p := range e.StorePaths {
			var built int
			m := nixpath.PathRe.FindStringSubmatch(string(p))
			if m == nil {
				log.Fatalf("unable to parse path %v", p)
			}
			mu.Lock()
			err := stmt.QueryRow(m[1]).Scan(&built)
			mu.Unlock()
			if (err == nil && built == 0) || err != nil {
				built = 0
				if !update {
					e.Active = false
				}
			}
			if update && (built != 1) {
				substituter.Path = path.Join(substituterOrigPath, m[1]+".narinfo")
				log.Debugf("fetching: %s\n", substituter.String())
				resp, err := http.Head(substituter.String())
				if err != nil || resp.StatusCode != 200 {
					built = 0
					e.Active = false
					log.Debugf("result: %s NOT found\n", m[1])
				} else {
					built = 1
					e.Active = e.Active && true
					log.Debugf("result: %s found\n", m[1])
				}
				timestamp := time.Now().Unix()
				mu.Lock()
				_, err = updateStmt.Exec(m[1], built, timestamp, timestamp)
				mu.Unlock()
				if err != nil {
					log.Fatal(err)
				}
			}
		}
		return e
	}
	p := parseq.New(10, process)
	go p.Start()
	go scanLines(p)

	for out := range p.Output {
		e := out.(Element)
		if !activate && (e.Active == invert) {
			continue
		}
		res, err := json.Marshal(e)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(string(res))
	}

	if err = db.Close(); err != nil {
		return err
	}
	return nil
}
