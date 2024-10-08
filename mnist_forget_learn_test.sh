# 覚えさせる数字忘れさせる数字のリスト
list_ewc_learn=(1)
list_forget=(9)

# テスト用のリスト
# list_ewc_learn=(1)
# list_forget=(0 1)
# ----------------------------------------------------
# 実験設定
cuda_num=1
# サンプルとして出力する画像の枚数
# n_samples=1000
n_samples=10000
dataset="fashion"
forgetting_method="random"
# yaml=$dataset".yaml"
contents_discription="Sensors 定量評価用 saを適用した場合の結果保存を追加"
# ----------------------------------

# 結果保存用ディレクトリ
result_save_dir="./results/text_results"

# 結果保存用ディレクトリが存在しない場合は作成
if [ ! -d "$result_save_dir" ]; then
    mkdir -p "$result_save_dir"
fi
# 結果出保存用のファイルを作成，名前は日付
file_name=$(date "+%Y_%m_%d_%H%M%S")_mnist_forget_learn_test.txt
result_dir_name="$result_save_dir/$file_name"

# 実験の日付を表示
echo "result file dir : $result_dir_name "| tee -a $result_dir_name
echo "experiment date: $(date "+%Y/%m/%d %H:%M:%S")" | tee -a $result_dir_name
# 実験の内容について記録
echo "experiment content: $contents_discription" | tee -a $result_dir_name
echo "dataset:$dataset , forgetting method:$forgetting_method " | tee -a $result_dir_name
# ファイルに変数の値を追記
echo "CUDA Number: $cuda_num" >> $result_dir_name
echo "Number of Samples: $n_samples" >> $result_dir_name


# すべての組わせをループで回す
for learn in ${list_ewc_learn[@]}; do
    echo "start VAE training. no train data class is $learn"
    vae_output_str=$(
        CUDA_VISIBLE_DEVICES="$cuda_num" python train_cvae.py --remove_label $learn --data_path ./dataset --dataset $dataset
        # 学習を早く終わらせるためにn_itersを5000に設定
        # CUDA_VISIBLE_DEVICES="$cuda_num" python train_cvae.py --n_iters 500 --remove_label $learn --data_path ./dataset --dataset $dataset
        ) 
    echo "start fim calculation for ewc and no sa ewc" 
        #output から save dir を抜き取る
        vae_save_dir=$(echo "$vae_output_str" | grep -oP 'vae save dir:\K[^\n]*')
        echo "VAE save dir is $vae_save_dir"
        echo "start FIM calculation"
        CUDA_VISIBLE_DEVICES="$cuda_num" python calculate_fim.py --ckpt_folder $vae_save_dir
    
    for forget in ${list_forget[@]}; do
        echo "forget: $forget, learn: $learn"    
        #　単純なファインチューニング
        echo "start finetuning"
            finetuning_output_str=$(
                CUDA_VISIBLE_DEVICES="$cuda_num" python train_finetuning.py --ckpt_folder $vae_save_dir --removed_label $forget --dataset $dataset
            )
            
            echo "$finetuning_output_str"
            # output から finetuning のsave dir を抜き取る
            finetuning_save_dir=$(echo "$finetuning_output_str" | grep -oP 'finetuning save dir:\K[^\n]*')
            echo "finetuning save dir is $finetuning_save_dir"
            # モデルの評価を行う
                # 10000枚の画像を生成
                CUDA_VISIBLE_DEVICES=$cuda_num python generate_samples.py --ckpt_folder $finetuning_save_dir --label_to_generate $learn --n_samples $n_samples
                # 分類機で精度を出す

                results=$(
                    CUDA_VISIBLE_DEVICES=$cuda_num python evaluate_with_classifier.py --sample_path $finetuning_save_dir --label_of_dropped_class $learn --dataset $dataset
                    )
                # 分類精度を記録する
                    echo "finetuning">>$result_dir_name
                    echo "checkpoint dir:(finetuning) $finetuning_save_dir"
                    echo "forget: $forget, learn: $learn">>$result_dir_name
                    echo "$results">>$result_dir_name
        

        # SAを実行せずに単純なEWCで評価
        echo "start no SA, EWC calculation" 
            echo "start EWC calculation"
            no_sa_ewc_output_str=$(
                CUDA_VISIBLE_DEVICES="$cuda_num" python train_ewc.py --ckpt_folder $vae_save_dir --removed_label $forget --dataset $dataset
            )
            no_sa_ewc_save_dir=$(echo "$no_sa_ewc_output_str" | grep -oP 'ewc save dir:\K[^\n]*')
            echo "no SA, EWC save dir is $no_sa_ewc_save_dir"
            # モデルの評価を行う
                # 10000枚の画像を生成
                CUDA_VISIBLE_DEVICES=$cuda_num python generate_samples.py --ckpt_folder $no_sa_ewc_save_dir --label_to_generate $learn --n_samples $n_samples
                # 分類機で精度を出す
                results=$(
                    CUDA_VISIBLE_DEVICES=$cuda_num python evaluate_with_classifier.py --sample_path $no_sa_ewc_save_dir --label_of_dropped_class $learn --dataset $dataset
                    )
                # 分類精度を記録する
                    echo "nosa,ewc">>$result_dir_name
                    echo "checkpoint dir:(nosa ewc) $no_sa_ewc_save_dir"
                    echo "forget: $forget, learn: $learn">>$result_dir_name
                    echo "$results">>$result_dir_name

        # sa を実行してからfinetuning をする
        echo "start SA and finetuning "
            echo "start SA calculation"
            # FIMはを適用した際のものを引き継ぐため再計算は不要
            sa_output_str=$(
                CUDA_VISIBLE_DEVICES="$cuda_num" python train_forget.py --ckpt_folder $vae_save_dir --label_to_drop $forget --lmbda 100 --forgetting_method $forgetting_method --dataset $dataset --embedding_label $learn
            ) 
            # output から sa vae のsave dir を抜き取る
            sa_save_dir=$(echo "$sa_output_str" | grep -oP 'sa save dir:\K[^\n]*')
            
            # saの結果出力がないならばプログラム全体を終了
            if [ -z "$sa_save_dir" ]; then
                echo "sa output is empty"
                exit 1
            fi
            # モデルの評価を行う
                # 10000枚の画像を生成
                CUDA_VISIBLE_DEVICES=$cuda_num python generate_samples.py --ckpt_folder $sa_save_dir --label_to_generate $learn --n_samples $n_samples
                # 分類機で精度を出す
                results=$(
                    CUDA_VISIBLE_DEVICES=$cuda_num python evaluate_with_classifier.py --sample_path $sa_save_dir --label_of_dropped_class $learn --dataset $dataset
                    )
                # 分類精度を記録する
                    echo "sa,only">>$result_dir_name
                    echo "checkpoint dir:(sa only) $sa_finetuning_save_dir"
                    echo "forget: $forget, learn: $learn">>$result_dir_name
                    echo "$results">>$result_dir_name        
        
            # SA　を適用したモデルにfinetuningを適用
            echo "SA save dir is $sa_save_dir"
            sa_finetuning_output_str=$(
                CUDA_VISIBLE_DEVICES="$cuda_num" python train_finetuning.py --ckpt_folder $sa_save_dir --removed_label $forget --dataset $dataset 
            )
            # finetuningの結果出力がないならばプログラム全体を終了
            if [ -z "$sa_finetuning_output_str" ]; then
                echo "finetuning output is empty"
                exit 1
            fi
            sa_finetuning_save_dir=$(echo "$sa_finetuning_output_str" | grep -oP 'finetuning save dir:\K[^\n]*')
            # モデルの評価を行う
                # 10000枚の画像を生成
                CUDA_VISIBLE_DEVICES=$cuda_num python generate_samples.py --ckpt_folder $sa_finetuning_save_dir --label_to_generate $learn --n_samples $n_samples
                # 分類機で精度を出す
                results=$(
                    CUDA_VISIBLE_DEVICES=$cuda_num python evaluate_with_classifier.py --sample_path $sa_finetuning_save_dir --label_of_dropped_class $learn --dataset $dataset
                    )
                # 分類精度を記録する
                    echo "sa,finetuning">>$result_dir_name
                    echo "checkpoint dir:(sa finetuning) $sa_finetuning_save_dir"
                    echo "forget: $forget, learn: $learn">>$result_dir_name
                    echo "$results">>$result_dir_name        
        
        # SA を適応して各モデルに足してEWCを適応
        echo "start SA, and EWC calculation"
            # fimはsa + ファインチューニングのモデルときに実行済み

            # SA　を適用したモデルにEWCを適用
            echo "SA save dir is $sa_save_dir"
            CUDA_VISIBLE_DEVICES="$cuda_num" python calculate_fim.py --ckpt_folder $sa_save_dir 
            sa_ewc_output_str=$(
                CUDA_VISIBLE_DEVICES="$cuda_num" python train_ewc.py --ckpt_folder $sa_save_dir --removed_label $forget --dataset $dataset
            )
            sa_ewc_save_dir=$(echo "$sa_ewc_output_str" | grep -oP 'ewc save dir:\K[^\n]*')
            # モデルの評価を行う
                # 10000枚の画像を生成
                CUDA_VISIBLE_DEVICES=$cuda_num python generate_samples.py --ckpt_folder $sa_ewc_save_dir --label_to_generate $learn --n_samples $n_samples
                # 分類機で精度を出す
                results=$(
                    CUDA_VISIBLE_DEVICES=$cuda_num python evaluate_with_classifier.py --sample_path $sa_ewc_save_dir --label_of_dropped_class $learn --dataset $dataset
                    )
                # 分類精度を記録する
                    echo "sa,ewc">>$result_dir_name
                    echo "checkpoint dir:(sa ewc) $sa_ewc_save_dir"
                    echo "forget: $forget, learn: $learn">>$result_dir_name
                    echo "$results">>$result_dir_name
    done
done

