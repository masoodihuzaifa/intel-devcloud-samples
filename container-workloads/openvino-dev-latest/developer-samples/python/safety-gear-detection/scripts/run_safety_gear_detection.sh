tag=2023.0.0
sample_name=safety_gear_detection_2023.0.0
# run on local machine 
sudo docker run  -e RUN_ON_PREM=data -it $sample_name:latest
# run on on prem cluster 
#sudo docker run   -it object_detection_$tag_fp16:latest
