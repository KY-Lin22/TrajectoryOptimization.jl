
function _backwardpass!(p::Problem,res::iLQRResults)
    N = p.N

    # Objective
    cost = p.cost

    dt = solver.dt

    X = p.X; U = p.U; K = res.K; d = res.d; S = res.S; s = res.s

    reset(res.bp)
    Qx = res.bp.Qx; Qu = res.bp.Qu; Qxx = res.bp.Qxx; Quu = res.bp.Quu; Qux = res.bp.Qux
    Quu_reg = res.bp.Quu_reg; Qux_reg = res.bp.Qux_reg

    # Boundary Conditions
    S[N], s[N] = taylor_expansion(cost, X[N])

    # Initialize expected change in cost-to-go
    Δv = zeros(2)

    # Backward pass
    k = N-1
    while k >= 1
        expansion = taylor_expansion(cost,x,u)
        Qxx[k],Quu[k],Qux[k],Qx[k],Qu[k] = expansion

        fdx, fdu = res.fdx[k], res.fdu[k]

        Qx[k] += fdx'*s[k+1]
        Qu[k] += fdu'*s[k+1]
        Qxx[k] += fdx'*S[k+1]*fdx
        Quu[k] += fdu'*S[k+1]*fdu
        Qux[k] += fdu'*S[k+1]*fdx

        if solver.opts.bp_reg_type == :state
            Quu_reg[k] = Quu[k] + res.ρ[1]*fdu'*fdu
            Qux_reg[k] = Qux[k] + res.ρ[1]*fdu'*fdx
        elseif solver.opts.bp_reg_type == :control
            Quu_reg[k] = Quu[k] + res.ρ[1]*I
            Qux_reg[k] = Qux[k]
        end

        # Regularization
        if !isposdef(Hermitian(Array(Quu_reg[k])))  # need to wrap Array since isposdef doesn't work for static arrays
            # increase regularization
            @logmsg InnerIters "Regularizing Quu "
            regularization_update!(res,solver,:increase)

            # reset backward pass
            k = N-1
            Δv[1] = 0.
            Δv[2] = 0.
            continue
        end

        # Compute gains
        K[k] = -Quu_reg[k]\Qux_reg[k]
        d[k] = -Quu_reg[k]\Qu[k]

        # Calculate cost-to-go (using unregularized Quu and Qux)
        s[k] = Qx[k] + K[k]'*Quu[k]*d[k] + K[k]'*Qu[k] + Qux[k]'*d[k]
        S[k] = Qxx[k] + K[k]'*Quu[k]*K[k] + K[k]'*Qux[k] + Qux[k]'*K[k]
        S[k] = 0.5*(S[k] + S[k]')

        # calculated change is cost-to-go over entire trajectory
        Δv[1] += d[k]'*Qu[k]
        Δv[2] += 0.5*d[k]'*Quu[k]*d[k]

        k = k - 1;
    end

    # decrease regularization after backward pass
    regularization_update!(res,solver,:decrease)

    return Δv
end
