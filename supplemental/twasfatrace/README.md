# twasfatrace

## Development

1. Build the container:
   ```
   podman build --platform linux/amd64 -t twasfatrace .
   ```
1. Push the image to the target environment ([OpenShift example](https://publib.boulder.ibm.com/httpserv/cookbook/Troubleshooting_Recipes-Troubleshooting_OpenShift_Recipes-OpenShift_Use_Image_Registry_Recipe.html))

## Push to Quay

```
podman push localhost/twasfatrace quay.io/ibm/containerdiag:twasfatrace
```
