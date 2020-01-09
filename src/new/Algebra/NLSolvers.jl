
# Mock

"""
    struct NewtonRaphsonSolver <:NonLinearSolver
      # Private fields
    end

Vanilla Newton-Raphson method
"""
struct NewtonRaphsonSolver <:NonLinearSolver
  ls::LinearSolver
  tol::Float64
  max_nliters::Int
end

struct NewtonRaphsonCache
  A::AbstractMatrix
  b::AbstractVector
  dx::AbstractVector
  ns::NumericalSetup
end

function solve!(x::AbstractVector,nls::NewtonRaphsonSolver,op::NonLinearOperator)
  b = residual(op, x)
  A = jacobian(op, x)
  dx = similar(b)
  ss = symbolic_setup(nls.ls, A)
  ns = numerical_setup(ss,A)
  _solve_nr!(x,A,b,dx,ns,nls,op)
  NewtonRaphsonCache(A,b,dx,ns)
end

function solve!(
  x::AbstractVector,nls::NewtonRaphsonSolver,op::NonLinearOperator,cache::NewtonRaphsonCache)
  b = cache.b
  A = cache.A
  dx = cache.dx
  ns = cache.ns
  residual!(b, op, x)
  jacobian!(A, op, x)
  numerical_setup!(ns,A)
  _solve_nr!(x,A,b,dx,ns,nls,op)
end

function _solve_nr!(x,A,b,dx,ns,nls,op)

  # Check for convergence on the initial residual
  isconv, conv0 = _check_convergence(nls,b)
  if isconv; return; end

  # Newton-like iterations
  for nliter in 1:nls.max_nliters

    # Solve linearized problem
    broadcast!(*,b,b,-1)
    solve!(dx,ns,b)
    broadcast!(+,x,x,dx)

    # Check convergence for the current residual
    residual!(b, op, x)
    isconv = _check_convergence(nls, b, conv0)
    if isconv; return; end

    if nliter == nls.max_nliters
      @unreachable
    end

    # Assemble jacobian (fast in-place version)
    # and prepare solver
    jacobian!(A, op, x)
    numerical_setup!(ns,A)

  end

end

function _check_convergence(nls,b)
  m0 = _inf_norm(b)
  (false, m0)
end

function _check_convergence(nls,b,m0)
  m = _inf_norm(b)
  m < nls.tol * m0
end

function _inf_norm(b)
  m = 0
  for bi in b
    m = max(m,abs(bi))
  end
  m
end

# Default concrete implementation

"""
    struct NLSolver <: NonLinearSolver
      # private fields
    end

The cache generated when using this solver has a field `result` that hosts the result
object generated by the underlying `nlsolve` function. It corresponds to the most latest solve.
"""
struct NLSolver <: NonLinearSolver
  ls::LinearSolver
  kwargs::Dict
end

"""
    NLSolver(ls::LinearSolver;kwargs...)
    NLSolver(;kwargs...)

Same kwargs as in `nlsolve`.
If `ls` is provided, it is not possible to use the `linsolve` kw-argument.
"""
function NLSolver(;kwargs...)
  ls = BackslashSolver()
  NLSolver(ls;kwargs...)
end

function NLSolver(ls::LinearSolver;kwargs...)
  @assert ! haskey(kwargs,:linsolve) "linsolve cannot be used here. It is managed internally"
  NLSolver(ls,kwargs)
end

mutable struct NLSolversCache <: GridapType
  f0::AbstractVector
  j0::AbstractMatrix
  df::OnceDifferentiable
  ns::NumericalSetup
  result
end

function solve!(x::AbstractVector,nls::NLSolver,op::NonLinearOperator)
  cache = _new_nlsolve_cache(x,nls,op)
  _nlsolve_with_updated_cache!(x,nls,op,cache)
  cache
end

function solve!(
  x::AbstractVector,nls::NLSolver,op::NonLinearOperator,cache::NLSolversCache)
  _update_nlsolve_cache!(cache,x,op)
  _nlsolve_with_updated_cache!(x,nls,op,cache)
end

function _nlsolve_with_updated_cache!(x,nls,op,cache)
  df = cache.df
  ns = cache.ns
  kwargs = nls.kwargs
  function linsolve!(x,A,b)
    numerical_setup!(ns,A)
    solve!(x,ns,b)
  end
  r = nlsolve(df,x;linsolve=linsolve!,kwargs...)
  cache.result = r
  x[:] .= r.zero
end

function _new_nlsolve_cache(x0,nls,op)
  f!(r,x) = residual!(r,op,x)
  j!(j,x) = jacobian!(j,op,x)
  f0 = residual(op,x0)
  j0 = jacobian(op,x0)
  df = OnceDifferentiable(f!,j!,x0,f0,j0)
  ss = symbolic_setup(nls.ls,j0)
  ns = numerical_setup(ss,j0)
  NLSolversCache(f0,j0,df,ns,nothing)
end

function _update_nlsolve_cache!(cache,x0,op)
  f!(r,x) = residual!(r,op,x)
  j!(j,x) = jacobian!(j,op,x)
  f0 = cache.f0
  j0 = cache.j0
  ns = cache.ns
  residual!(f0,op,x0)
  jacobian!(j0,op,x0)
  df = OnceDifferentiable(f!,j!,x0,f0,j0)
  numerical_setup!(ns,j0)
  NLSolversCache(f0,j0,df,ns,nothing)
end


