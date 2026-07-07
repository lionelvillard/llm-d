#!/usr/bin/env bash
test_assert_eq_passes_on_equal() {
  assert_eq "a" "a" "identical strings are equal"
}
test_assert_contains_finds_substring() {
  assert_contains "hello world" "world" "substring is found"
}
