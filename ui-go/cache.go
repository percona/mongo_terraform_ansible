package main

import (
	"sync"
	"time"
)

const cacheTTL = 5 * time.Minute

type cacheEntry struct {
	data interface{}
	ts   time.Time
}

var cacheMu sync.RWMutex
var imgCache = map[string]cacheEntry{}

func cacheGet(key string) (interface{}, bool) {
	cacheMu.RLock()
	defer cacheMu.RUnlock()
	e, ok := imgCache[key]
	if !ok || time.Since(e.ts) > cacheTTL {
		return nil, false
	}
	return e.data, true
}

func cacheSet(key string, data interface{}) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	imgCache[key] = cacheEntry{data, time.Now()}
}
