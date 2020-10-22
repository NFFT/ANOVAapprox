abstract type nperiodic_approx <: fun_approx end

function nperiodic_approx( X::Matrix{Float64}, y::Vector{ComplexF64}, ds::Integer, N::Vector{Int64}; method::String="lsqr", basis::String="cosine", active_set=false )::nperiodic_approx
    d = size(X, 1)
    M = size(X, 2)

    if length(y) != M 
        error( "Length mismatch in y." )
    end

    if ds < 1 || ds > d 
        error( "Superposition dimension mismatch." )
    end

    if length(N) != ds 
        error( "Bandwidths length mismatch." )
    end

    if active_set == false
        U = get_superposition_set(d, ds)
    else
        U = active_set
    end

    if basis == "cosine"
        if maximum(X) > 1.0 || minimum(X) < 0.0
          error( "Your nodes have to be between zero and one.")
        end
        X ./= 2.0
    elseif basis == "cheb"
        if maximum(X) >= 1.0 || minimum(X) <= -1.0
            error( "Your nodes have to be between minus one and one.")
        end
        X = acos.( X )
        X ./= 2.0*pi
    else 
        error("basis not implemented yet")
    end

    tmp = zeros( Int64, ds+1 )
    tmp[2:end] = N
    bandwidths = [ fill(tmp[length(u)+1], length(u)) for u in U ]
 
    setting = [ (u = U[idx], mode = NFCTstuff, bandwidths = bandwidths[idx]) for idx in 1:length(U) ]
    F = GroupedTransform(setting, X)

    if method == "lsqr"
      return nperiodic_approx_scat_lsqr{d,ds}(basis, X, y, U, F, N)
    elseif method == "fista"
      return nperiodic_approx_scat_fista{d,ds}(basis, X, y, U, F, N)
    else
      error("method not implemented yet")
    end
end

function get_L2error( approx::nperiodic_approx, norm::Float64, fc_fun::Function, lambda::Float64 ) 
    err2 = norm^2

    for j = 1:length(approx.U)
        u = approx.U[j]

        if u == []
            k = zeros(Int64, size(approx.X, 1))
            err2 += abs(fc_fun(k) - (approx.fc[lambda])[u][1])^2 - abs( fc_fun(k) )^2
            continue
        end
            
        N = approx.N[length(u)]*ones(Int64, length(u))
        I_hat = NFFTstuff.nfft_index_set_without_zeros(N)
        I = zeros( Int64, size(approx.X, 1), (length(u) == 1) ? length(I_hat) : size(I_hat, 2))
        I[u,:] = I_hat 

        for i = 1:size(I, 2)
            err2 += abs(fc_fun(I[:,i]) - (approx.fc[lambda])[u][i])^2 - abs( fc_fun(I[:,i]) )^2
        end
    end

    return sqrt(err2)/norm
end

function get_L2error( approx::nperiodic_approx, norm::Float64, fc_fun::Function ) 
    return Dict( λ => get_L2error(approx, norm, fc_fun, λ) for λ in collect(keys(approx.fc)))
end


function evaluate( approx::nperiodic_approx, X::Matrix{Float64}, lambda::Float64 )::Vector{ComplexF64}
    if size(X,1) != size(approx.X,1)
        error( "Matrix size mismatch." )
    end

    F = GroupedTransform(approx.trafo.setting, X./2)
    fc = approx.fc[lambda]

    return F*fc
end

function evaluate( approx::nperiodic_approx, X::Matrix{Float64} )
    return Dict( λ => evaluate(approx, X, λ) for λ in collect(keys(approx.fc)))
end

function getBasisCoefficients( approx::nperiodic_approx )
    fc = Dict( )
    for λ in collect(keys(approx.fc))
        for (k, v) in approx.fc[λ]
            fc_lambda = GroupedCoeff(approx.trafo.setting, v.data)
            for u in approx.U 
                if u != []
                    fc_lambda[u] = fc_lambda[u] ./ (sqrt(2)^length(u))
                end
            end
            fc[λ] = fc_lambda
        end
    end
    return Dict( λ => approx.fc[λ] )
end