#!/usr/bin/python
#
# A quick benchmark to check the health of EC2 instance.
#
# http://en.literateprograms.org/Pi_with_Machin's_formula_%28Python%29

import sys

def arccot(x, unity):
    sum = xpower = unity // x
    n = 3
    sign = -1
    while 1:
        xpower = xpower // (x*x)
        term = xpower // n
        if not term:
            break
        sum += sign * term
        sign = -sign
        n += 2
    return sum

def pi(digits):
    unity = 10**(digits + 10)
    pi = 4 * (4*arccot(5, unity) - arccot(239, unity))
    return pi // 10**10

pi = pi(int(sys.argv[1]))

print pi % 1000

