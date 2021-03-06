using LightGBM
using Test
using DelimitedFiles
using StatsBase
using DataFrames,CSV,HTTP

@testset "LightGBM.jl" begin
    # Use binary example for generic tests.
    println("Start runtest.jl ENV[\"LIGHTGBM_PATH\"] is ",ENV["LIGHTGBM_PATH"])
    if isfile( joinpath(ENV["LIGHTGBM_PATH"],"examples/binary_classification/binary.test") )
        binary_test = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/binary_classification/binary.test"), '\t');
        binary_train = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/binary_classification/binary.train"), '\t');
    else
        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/binary_classification/binary.test");
        work=String(res.body);
        binary_test =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));

        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/binary_classification/binary.train");
        work=String(res.body);
        binary_train =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));
    end

    X_train = binary_train[:, 2:end]
    y_train = binary_train[:, 1]
    X_test = binary_test[:, 2:end]
    y_test = binary_test[:, 1]

    # Test wrapper functions.
    train_ds = LightGBM.LGBM_DatasetCreateFromMat(X_train, "objective=binary");
    @test LightGBM.LGBM_DatasetGetNumData(train_ds) == 7000
    @test LightGBM.LGBM_DatasetGetNumFeature(train_ds) == 28
    @test LightGBM.LGBM_DatasetSetField(train_ds, "label", y_train) == nothing
    @test LightGBM.LGBM_DatasetGetField(train_ds, "label") == y_train
    bst = LightGBM.LGBM_BoosterCreate(train_ds, "lambda_l1=10. metric=auc, verbosity=-1")

    test_ds = LightGBM.LGBM_DatasetCreateFromMat(X_test, "objective=binary", train_ds);
    @test LightGBM.LGBM_DatasetSetField(test_ds, "label", y_test) == nothing
    @test LightGBM.LGBM_BoosterAddValidData(bst, test_ds) == nothing
    @test LightGBM.LGBM_BoosterUpdateOneIter(bst) == 0
    @test LightGBM.LGBM_BoosterGetEvalCounts(bst) == 1
    @test LightGBM.LGBM_BoosterGetEvalNames(bst)[1] == "auc"

    # Test binary estimator.
    estimator = LightGBM.LGBMBinary(num_iterations = 20,
                                    learning_rate = .1,
                                    early_stopping_round = 1,
                                    feature_fraction = .8,
                                    bagging_fraction = .9,
                                    bagging_freq = 1,
                                    num_leaves = 1000,
                                    metric = ["auc", "binary_logloss"],
                                    is_training_metric = true,
                                    max_bin = 255,
                                    min_sum_hessian_in_leaf = 0.,
                                    min_data_in_leaf = 1);

    # Test fitting.
    LightGBM.fit(estimator, X_train, y_train, verbosity = 0);
    LightGBM.fit(estimator, X_train, y_train, (X_test, y_test), verbosity = 0); #boost_from_average=false

    # Test setting feature names
    jl_feature_names = ["testname_$i" for i in 1:28]
    LightGBM.LGBM_DatasetSetFeatureNames(estimator.booster.datasets[1], jl_feature_names)
    lgbm_feature_names = LightGBM.LGBM_DatasetGetFeatureNames(estimator.booster.datasets[1])
    @test jl_feature_names == lgbm_feature_names

    # Test prediction, and loading and saving models.
    test_filename = tempname()
        LightGBM.savemodel(estimator, test_filename);
    try
        pre = LightGBM.predict(estimator, X_train, verbosity = 0);
        LightGBM.loadmodel(estimator, test_filename);
        post = LightGBM.predict(estimator, X_train, verbosity = 0);
        @test isapprox(pre, post)
    finally
        rm(test_filename);
    end

    # Test cross-validation.
    splits = (collect(1:3500), collect(3501:7000));
    LightGBM.cv(estimator, X_train, y_train, splits; verbosity = 0);

    # Test exhaustive search.
    params = [Dict(:num_iterations => num_iterations,
                   :num_leaves => num_leaves) for
                   num_iterations in (1, 2),
                   num_leaves in (5, 10)];
    LightGBM.search_cv(estimator, X_train, y_train, splits, params; verbosity = 0);

    # Test regression estimator.
    if isfile( joinpath(ENV["LIGHTGBM_PATH"],"examples/regression/regression.test") )
        regression_test = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/regression/regression.test"), '\t');
        regression_train = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/regression/regression.train"), '\t');
    else
        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/regression/regression.test");
        work=String(res.body);
        regression_test =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));

        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/regression/regression.train");
        work=String(res.body);
        regression_train =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));
    end

    X_train = regression_train[:, 2:end]
    y_train = regression_train[:, 1]
    X_test = regression_test[:, 2:end]
    y_test = regression_test[:, 1]

    estimator = LightGBM.LGBMRegression(num_iterations = 100,
                                        learning_rate = .05,
                                        feature_fraction = .9,
                                        bagging_fraction = .8,
                                        bagging_freq = 5,
                                        num_leaves = 31,
                                        metric = ["l2"],
                                        metric_freq = 1,
                                        is_training_metric = true,
                                        max_bin = 255,
                                        min_sum_hessian_in_leaf = 5.,
                                        min_data_in_leaf = 100,
                                        max_depth = -1);

    scores = LightGBM.fit(estimator, X_train, y_train, (X_test, y_test), verbosity = 0);
    @test scores["test_1"]["l2"][end] < .5

    # Test multiclass estimator.
    if isfile( joinpath(ENV["LIGHTGBM_PATH"],"examples/multiclass_classification/multiclass.test") )
        multiclass_test = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/multiclass_classification/multiclass.test"), '\t');
        multiclass_train = readdlm(joinpath(ENV["LIGHTGBM_PATH"] , "examples/multiclass_classification/multiclass.train"), '\t');
    else
        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/multiclass_classification/multiclass.test");
        work=String(res.body);
        multiclass_test =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));

        res = HTTP.get("https://raw.githubusercontent.com/microsoft/LightGBM/v2.3.1/examples/multiclass_classification/multiclass.train");
        work=String(res.body);
        multiclass_train =convert(Matrix,CSV.read(IOBuffer(work),delim='\t',header=false));
    end

    X_train = Matrix(multiclass_train[:, 2:end])
    y_train = Array(multiclass_train[:, 1])
    X_test = Matrix(multiclass_test[:, 2:end])
    y_test = Array(multiclass_test[:, 1])

    estimator = LightGBM.LGBMMulticlass(num_iterations = 100,
                                        learning_rate = .05,
                                        feature_fraction = .9,
                                        bagging_fraction = .8,
                                        bagging_freq = 5,
                                        num_leaves = 31,
                                        metric = ["multi_logloss"],
                                        metric_freq = 1,
                                        is_training_metric = true,
                                        max_bin = 255,
                                        min_sum_hessian_in_leaf = 5.,
                                        min_data_in_leaf = 100,
                                        num_class = 5,
                                        early_stopping_round = 10);

    scores = LightGBM.fit(estimator, X_train, y_train, (X_test, y_test), verbosity = 0);
    @test scores["test_1"]["multi_logloss"][end] < 1.4

    # Test row major multiclass
    X_train = Matrix(multiclass_train[:, 2:end]')
    X_test = Matrix(multiclass_test[:, 2:end]')

    estimator = LightGBM.LGBMMulticlass(num_iterations = 100,
                                        learning_rate = .05,
                                        feature_fraction = .9,
                                        bagging_fraction = .8,
                                        bagging_freq = 5,
                                        num_leaves = 31,
                                        metric = ["multi_logloss"],
                                        metric_freq = 1,
                                        is_training_metric = true,
                                        max_bin = 255,
                                        min_sum_hessian_in_leaf = 5.,
                                        min_data_in_leaf = 100,
                                        num_class = 5,
                                        early_stopping_round = 10);

    scores = LightGBM.fit(estimator, X_train, y_train, (X_test, y_test), verbosity = 0,
                          is_row_major = true);
    @test scores["test_1"]["multi_logloss"][end] < 1.4

    include("weightsTest.jl")
    include("initScoreTest.jl")

end