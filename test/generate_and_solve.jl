#  Copyright 2017, Iain Dunning, Joey Huchette, Miles Lubin, and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.

# The tests here check JuMP's model generation and communication with solvers.
# Model generation is checked by comparing the internal model with a serialized
# test model (in MOIU's lightweight text format).
# Communication with solvers is tested by using a mock solver with solution data
# that we feed to it. Prior to using this testing approach, we would test JuMP
# by calling real solvers, which was flakey and slow.

# Note: No attempt is made to use correct solution data. We're only testing
# that the plumbing works. This could change if JuMP gains the ability to verify
# feasibility independently of a solver.

@testset "Generation and solve with fake solver" begin
    @testset "LP" begin
        m = Model()
        @variable(m, x <= 2.0)
        @variable(m, y >= 0.0)
        @objective(m, Min, -x)

        c = @constraint(m, x + y <= 1)

        JuMP.set_name(JuMP.UpperBoundRef(x), "xub")
        JuMP.set_name(JuMP.LowerBoundRef(y), "ylb")
        JuMP.set_name(c, "c")

        modelstring = """
        variables: x, y
        minobjective: -1.0*x
        xub: x <= 2.0
        ylb: y >= 0.0
        c: x + y <= 1.0
        """

        model = JuMP.JuMPMOIModel{Float64}()
        MOIU.loadfromstring!(model, modelstring)
        MOIU.test_models_equal(JuMP.caching_optimizer(m).model_cache, model, ["x","y"], ["c", "xub", "ylb"])

        JuMP.optimize!(m, with_optimizer(MOIU.MockOptimizer,
                                         JuMP.JuMPMOIModel{Float64}(),
                                         eval_objective_value=false))

        mockoptimizer = JuMP.caching_optimizer(m).optimizer
        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ObjectiveValue(), -1.0)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(y), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(c), -1.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(JuMP.UpperBoundRef(x)), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(JuMP.LowerBoundRef(y)), 1.0)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value(x) == 1.0
        @test JuMP.result_value(y) == 0.0
        @test JuMP.result_value(x + y) == 1.0
        @test JuMP.objective_value(m) == -1.0

        @test JuMP.dual_status(m) == MOI.FeasiblePoint
        @test JuMP.result_dual(c) == -1
        @test JuMP.result_dual(JuMP.UpperBoundRef(x)) == 0.0
        @test JuMP.result_dual(JuMP.LowerBoundRef(y)) == 1.0
    end

    @testset "LP (Direct mode)" begin
        mockoptimizer = MOIU.MockOptimizer(JuMP.JuMPMOIModel{Float64}(),
                                           eval_objective_value=false)

        m = JuMP.direct_model(mockoptimizer)
        @variable(m, x <= 2.0)
        @variable(m, y >= 0.0)
        @objective(m, Min, -x)

        c = @constraint(m, x + y <= 1)
        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ObjectiveValue(), -1.0)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(y), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(c), -1.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(JuMP.UpperBoundRef(x)), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(JuMP.LowerBoundRef(y)), 1.0)

        JuMP.optimize!(m)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value(x) == 1.0
        @test JuMP.result_value(y) == 0.0
        @test JuMP.result_value(x + y) == 1.0
        @test JuMP.objective_value(m) == -1.0

        @test JuMP.dual_status(m) == MOI.FeasiblePoint
        @test JuMP.result_dual(c) == -1
        @test JuMP.result_dual(JuMP.UpperBoundRef(x)) == 0.0
        @test JuMP.result_dual(JuMP.LowerBoundRef(y)) == 1.0
    end

    # TODO: test Manual mode

    @testset "IP" begin
        # Tests the solver= keyword.
        m = Model(with_optimizer(MOIU.MockOptimizer,
                                 JuMP.JuMPMOIModel{Float64}(),
                                 eval_objective_value=false),
                  caching_mode = MOIU.Automatic)
        @variable(m, x == 1.0, Int)
        @variable(m, y, Bin)
        @objective(m, Max, x)

        JuMP.set_name(JuMP.FixRef(x), "xfix")
        JuMP.set_name(JuMP.IntegerRef(x), "xint")
        JuMP.set_name(JuMP.BinaryRef(y), "ybin")

        modelstring = """
        variables: x, y
        maxobjective: x
        xfix: x == 1.0
        xint: x in Integer()
        ybin: y in ZeroOne()
        """

        model = JuMP.JuMPMOIModel{Float64}()
        MOIU.loadfromstring!(model, modelstring)
        MOIU.test_models_equal(JuMP.caching_optimizer(m).model_cache, model, ["x","y"], ["xfix", "xint", "ybin"])

        MOIU.attachoptimizer!(m)

        mockoptimizer = JuMP.caching_optimizer(m).optimizer
        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ObjectiveValue(), 1.0)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(y), 0.0)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.NoSolution)

        JuMP.optimize!(m)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value(x) == 1.0
        @test JuMP.result_value(y) == 0.0
        @test JuMP.objective_value(m) == 1.0

        @test !JuMP.has_result_dual(m, typeof(JuMP.FixRef(x)))
        @test !JuMP.has_result_dual(m, typeof(JuMP.IntegerRef(x)))
        @test !JuMP.has_result_dual(m, typeof(JuMP.BinaryRef(y)))
    end

    @testset "QCQP" begin
        m = Model()
        @variable(m, x)
        @variable(m, y)
        @objective(m, Min, x^2)

        @constraint(m, c1, 2x*y <= 1)
        @constraint(m, c2, y^2 == x^2)
        @constraint(m, c3, 2x + 3y*x >= 2)

        modelstring = """
        variables: x, y
        minobjective: 1*x*x
        c1: 2*x*y <= 1.0
        c2: 1*y*y + -1*x*x == 0.0
        c3: 2x + 3*y*x >= 2.0
        """

        model = JuMP.JuMPMOIModel{Float64}()
        MOIU.loadfromstring!(model, modelstring)
        MOIU.test_models_equal(JuMP.caching_optimizer(m).model_cache, model, ["x","y"], ["c1", "c2", "c3"])

        JuMP.optimize!(m, with_optimizer(MOIU.MockOptimizer,
                                         JuMP.JuMPMOIModel{Float64}(),
                                         eval_objective_value=false))

        mockoptimizer = JuMP.caching_optimizer(m).optimizer
        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ObjectiveValue(), -1.0)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(y), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(c1), -1.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(c2), 2.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(c3), 3.0)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value(x) == 1.0
        @test JuMP.result_value(y) == 0.0
        @test JuMP.objective_value(m) == -1.0

        @test JuMP.dual_status(m) == MOI.FeasiblePoint
        @test JuMP.result_dual(c1) == -1.0
        @test JuMP.result_dual(c2) == 2.0
        @test JuMP.result_dual(c3) == 3.0
    end

    @testset "SOC" begin
        m = Model()
        @variables m begin
            x
            y
            z
        end
        @objective(m, Max, 1.0*x)
        @constraint(m, varsoc, [x,y,z] in SecondOrderCone())
        # Equivalent to `[x+y,z,1.0] in SecondOrderCone()`
        @constraint(m, affsoc, [x+y,z,1.0] in MOI.SecondOrderCone(3))
        @constraint(m, rotsoc, [x+1,y,z] in RotatedSecondOrderCone())

        modelstring = """
        variables: x, y, z
        maxobjective: 1.0*x
        varsoc: [x,y,z] in SecondOrderCone(3)
        affsoc: [x+y,z,1.0] in SecondOrderCone(3)
        rotsoc: [x+1,y,z] in RotatedSecondOrderCone(3)
        """

        model = JuMP.JuMPMOIModel{Float64}()
        MOIU.loadfromstring!(model, modelstring)
        MOIU.test_models_equal(JuMP.caching_optimizer(m).model_cache, model, ["x","y","z"], ["varsoc", "affsoc", "rotsoc"])

        mockoptimizer = MOIU.MockOptimizer(JuMP.JuMPMOIModel{Float64}(),
                                           eval_objective_value=false,
                                           eval_variable_constraint_dual=false)
        MOIU.resetoptimizer!(m, mockoptimizer)
        MOIU.attachoptimizer!(m)

        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(y), 0.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(z), 0.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(varsoc), [-1.0,-2.0,-3.0])
        MOI.set(mockoptimizer, MOI.ConstraintDual(), JuMP.optimizer_index(affsoc), [1.0,2.0,3.0])

        JuMP.optimize!(m)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value(x) == 1.0
        @test JuMP.result_value(y) == 0.0
        @test JuMP.result_value(z) == 0.0

        @test JuMP.has_result_dual(m, typeof(varsoc))
        @test JuMP.result_dual(varsoc) == [-1.0, -2.0, -3.0]

        @test JuMP.has_result_dual(m, typeof(affsoc))
        @test JuMP.result_dual(affsoc) == [1.0, 2.0, 3.0]
    end

    @testset "SDP" begin
        m = Model()
        @variable(m, x[1:2,1:2], Symmetric)
        set_name(x[1,1], "x11")
        set_name(x[1,2], "x12")
        set_name(x[2,2], "x22")
        @static if VERSION < v"0.7-"
            @objective(m, Max, trace(x))
        else
            @objective(m, Max, tr(x))
        end
        var_psd = @constraint(m, x in PSDCone())
        set_name(var_psd, "var_psd")
        sym_psd = @constraint(m, Symmetric(x - [1.0 0.0; 0.0 1.0]) in PSDCone())
        set_name(sym_psd, "sym_psd")
        con_psd = @SDconstraint(m, x ⪰ [1.0 0.0; 0.0 1.0])
        set_name(con_psd, "con_psd")

        modelstring = """
        variables: x11, x12, x22
        maxobjective: 1.0*x11 + 1.0*x22
        var_psd: [x11,x12,x22] in PositiveSemidefiniteConeTriangle(2)
        sym_psd: [x11 + -1.0,x12,x22 + -1.0] in PositiveSemidefiniteConeTriangle(2)
        con_psd: [x11 + -1.0,x12,x12,x22 + -1.0] in PositiveSemidefiniteConeSquare(2)
        """

        model = JuMP.JuMPMOIModel{Float64}()
        MOIU.loadfromstring!(model, modelstring)
        MOIU.test_models_equal(JuMP.caching_optimizer(m).model_cache, model,
                               ["x11","x12","x22"],
                               ["var_psd", "sym_psd", "con_psd"])

        mockoptimizer = MOIU.MockOptimizer(JuMP.JuMPMOIModel{Float64}(),
                                           eval_objective_value=false,
                                           eval_variable_constraint_dual=false)
        MOIU.resetoptimizer!(m, mockoptimizer)
        MOIU.attachoptimizer!(m)

        MOI.set(mockoptimizer, MOI.TerminationStatus(), MOI.Success)
        MOI.set(mockoptimizer, MOI.ResultCount(), 1)
        MOI.set(mockoptimizer, MOI.PrimalStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.DualStatus(), MOI.FeasiblePoint)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x[1,1]), 1.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x[1,2]), 2.0)
        MOI.set(mockoptimizer, MOI.VariablePrimal(), JuMP.optimizer_index(x[2,2]), 4.0)
        MOI.set(mockoptimizer, MOI.ConstraintDual(),
                JuMP.optimizer_index(var_psd), [1.0, 2.0, 3.0])
        MOI.set(mockoptimizer, MOI.ConstraintDual(),
                JuMP.optimizer_index(sym_psd), [4.0, 5.0, 6.0])
        MOI.set(mockoptimizer, MOI.ConstraintDual(),
                JuMP.optimizer_index(con_psd), [7.0, 8.0, 9.0, 10.0])

        JuMP.optimize!(m)

        #@test JuMP.isattached(m)
        @test JuMP.has_result_values(m)

        @test JuMP.termination_status(m) == MOI.Success
        @test JuMP.primal_status(m) == MOI.FeasiblePoint

        @test JuMP.result_value.(x) == [1.0 2.0; 2.0 4.0]
        @test JuMP.has_result_dual(m, typeof(var_psd))
        @test JuMP.result_dual(var_psd) isa Symmetric
        @test JuMP.result_dual(var_psd) == [1.0 2.0; 2.0 3.0]
        @test JuMP.has_result_dual(m, typeof(sym_psd))
        @test JuMP.result_dual(sym_psd) isa Symmetric
        @test JuMP.result_dual(sym_psd) == [4.0 5.0; 5.0 6.0]
        @test JuMP.has_result_dual(m, typeof(con_psd))
        @test JuMP.result_dual(con_psd) isa Matrix
        @test JuMP.result_dual(con_psd) == [7.0 9.0; 8.0 10.0]

    end

    @testset "Provide factory in `optimize` in Direct mode" begin
        mockoptimizer = MOIU.MockOptimizer(JuMP.JuMPMOIModel{Float64}())
        model = JuMP.direct_model(mockoptimizer)
        @test_throws ErrorException JuMP.optimize!(model, with_optimizer(MOIU.MockOptimizer, JuMP.JuMPMOIModel{Float64}()))
    end

    @testset "Provide factory both in `Model` and `optimize`" begin
        model = Model(with_optimizer(MOIU.MockOptimizer, JuMP.JuMPMOIModel{Float64}()))
        @test_throws ErrorException JuMP.optimize!(model, with_optimizer(MOIU.MockOptimizer, JuMP.JuMPMOIModel{Float64}()))
    end
end
