proc roundWithTolerance*(n: uint64, inverseTolerance: uint64 = 100): uint64 =
  ## Calculates the "most rounded" version of a positive integer `n` such that
  ## the relative rounding error does not exceed some tolerance. "Most rounded"
  ## means having the most trailing zeros.
  ##
  ## Tolerance is specified as the inverse of the tolerance percentage to avoid
  ## floating-point math. The default tolerance is 1%.
  ##
  ## The relative error condition is interpreted as:
  ##   abs(n - r) / n <= 1 / inverseTolerance
  ## which, using integer math, becomes:
  ##   inverseTolerance * abs(n - r) <= n
  ## where `r` is the rounded value.
  ##
  ## Rounding for a given power of 10 (`p`) uses standard "round half up":
  ##   r = ((n + p div 2) div p) * p
  ##
  ## Note: With 1% tolerance:
  ##   395 -> 400: Error=5. Check: 100 * 5 <= 395 => 500 <= 395 is False. Still 395.
  ##   499 -> 500: Error=1. Check: 100 * 1 <= 499 => 100 <= 499 is True. Output: 500.
  ##   999 -> 1000: Error=1. Check: 100 * 1 <= 999 => 100 <= 999 is True. Output: 1000.
  ##   4571 -> 4600: r(10)=4570 (err=1 OK). r(100)=4600 (err=29 OK). r(1000)=5000 (err=429 Bad). Output: 4600.

  assert n > 0, "Input number must be positive"

  # Use int64 for intermediate calculations to prevent overflow with large numbers
  let n64 = n.int64
  var bestR: int64 = n64 # Initialize with the original number
  var p: int64 = 10      # Start with rounding to the nearest 10

  while true:
    # Calculate the rounding divisor (half of p for round-to-nearest)
    let halfP = p div 2

    # Check for potential overflow when adding halfP
    if n64 > high(int64) - halfP:
      break

    # Calculate the rounded value `r` to the nearest `p`
    let rIntermediate = (n64 + halfP) div p

    # Check for potential overflow when multiplying back by p
    if p != 0 and abs(rIntermediate) > (high(int64) div abs(p)):
        break
    let r = rIntermediate * p

    # Calculate absolute error
    let absErr = abs(n64 - r)

    # Check for potential overflow in the error condition calculation (inverseTolerance * absErr)
    # If absErr is already huge, the condition likely fails anyway
    if inverseTolerance.int64 * absErr > high(int64):
      break # Error calculation would overflow, implies error is too large

    # Check the error condition: inverseTolerance * abs(n - r) <= n
    if inverseTolerance.int64 * absErr <= n64:
      # Acceptable rounding found. Update best result and try next power of 10.
      bestR = r

      # Prepare next power of 10
      # Check for overflow before multiplying p by 10
      if p > high(int64) div 10:
        break # Next power of 10 would overflow int64

      p *= 10

      # Optimization: If rounding resulted in 0, further rounding won't improve
      # or change the result in a way that passes the error check.
      if r == 0:
          break

    else:
      # Rounding error is too large. Stop and return the last acceptable result.
      break

  result = bestR.uint64
