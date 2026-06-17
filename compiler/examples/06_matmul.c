// 3x3 integer matrix multiply C = A * B, row-major flat arrays.
int A[9];
int B[9];
int Cm[9];

void matmul(int *a, int *b, int *c){
    int i; int j; int k; int sum;
    i = 0;
    while (i < 3){
        j = 0;
        while (j < 3){
            sum = 0;
            k = 0;
            while (k < 3){
                sum = sum + a[i*3+k] * b[k*3+j];
                k = k + 1;
            }
            c[i*3+j] = sum;
            j = j + 1;
        }
        i = i + 1;
    }
}

int main(void){
    int i;
    // A = [1 2 3; 4 5 6; 7 8 9]
    i = 0; while (i < 9){ A[i] = i + 1; i = i + 1; }
    // B = identity
    i = 0; while (i < 9){ B[i] = 0; i = i + 1; }
    B[0] = 1; B[4] = 1; B[8] = 1;
    matmul(A, B, Cm);
    // A*I = A, so print all of Cm
    i = 0; while (i < 9){ putint(Cm[i]); i = i + 1; }
    return 0;
}
